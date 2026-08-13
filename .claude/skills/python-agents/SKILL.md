---
name: python-agents
description: Python for HELIOS agent scripting and ML tooling — uv-managed projects, the JSON-over-stdio subprocess contract with the C# orchestrator, pydantic v2 models, asyncio LLM fan-out, and pyright-strict typing. Use when writing or reviewing Python agents, scripts, or ML utilities in the platform.
---

Hub-and-spoke rule: Python is a spoke — every Python process is launched by the C# orchestrator (subprocess with JSON-over-stdio, or long-running gRPC) and never touches databases, cloud services, or provider APIs directly; credentials live only in the C# hub.

## Project layout: uv everywhere

`uv` manages standalone agent projects; never invoke `pip`. One bare-`python3` exception:
the dependency-free spoke (`src/ai/python`) is deliberately runnable with no environment
at all — CI (`python3 -m pytest tests`, CLAUDE.md) and `PythonInsightsSpoke` invoke it
bare (see `references/testing-and-libraries.md`).

```toml
# pyproject.toml
[project]
name = "helios-agent-summarize"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = ["pydantic>=2.7", "anyio>=4"]

[dependency-groups]
dev = ["pytest>=8", "pyright>=1.1.390", "ruff>=0.6"]
```

Workflow: `uv lock` after editing dependencies, `uv sync` to materialize, `uv run pytest` / `uv run pyright` to execute. Commit `uv.lock` — the orchestrator relies on reproducible agent environments.

## The spoke contract: JSON over stdio

The exact pattern every one-shot agent follows — one request on stdin, one response on stdout, logs to stderr, exit 0 (nonzero only when no JSON response could be produced):

```python
import json, sys, logging

logging.basicConfig(stream=sys.stderr, level=logging.INFO)  # stderr ONLY

def main() -> int:
    raw = sys.stdin.read()                       # exactly one JSON document
    req = AgentRequest.model_validate_json(raw)
    try:
        result = run(req)
        resp = AgentResponse(ok=True, result=result)
    except Exception:
        logging.exception("agent failed")
        resp = AgentResponse(ok=False, error="internal_error")
    sys.stdout.write(resp.model_dump_json())     # exactly one JSON document
    sys.stdout.flush()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

Rules: nothing but the response JSON ever goes to stdout (no prints, no progress bars); the hub treats stderr as the log stream and stdout as the wire. Inputs that would need secrets (API keys, connection strings) are not accepted — the hub performs those calls itself and passes data in.

When per-call process spawn latency matters (interactive features, >~10 calls/sec), switch to a long-running gRPC service the hub starts and supervises; same rule applies — the proto surface accepts data, never credentials or connection targets.

## Models: pydantic v2

Every request/response crossing the stdio or gRPC boundary is a pydantic model — validation errors become structured failures instead of stack traces mid-agent:

```python
from pydantic import BaseModel, Field

class AgentRequest(BaseModel, frozen=True):
    task: str
    documents: list[str] = Field(min_length=1)
    max_tokens: int = Field(default=1024, ge=1, le=200_000)

class AgentResponse(BaseModel):
    ok: bool
    result: str | None = None
    error: str | None = None
```

Use `model_validate_json` / `model_dump_json` (v2 API — not the removed v1 `parse_raw`/`json()`). `frozen=True` on requests keeps agent logic honest. These models mirror C# record types in the hub; change them in lockstep.

## Concurrency: asyncio fan-out

When the hub hands an agent multiple LLM sub-calls to coordinate (routed back through the hub's local endpoint), fan out with a bounded gather:

```python
import asyncio

async def fan_out(prompts: list[str], call: CallFn, limit: int = 5) -> list[str]:
    sem = asyncio.Semaphore(limit)
    async def one(p: str) -> str:
        async with sem:
            return await call(p)
    return await asyncio.gather(*(one(p) for p in prompts))
```

Prefer `asyncio.TaskGroup` (3.11+) when partial failure should cancel siblings; `gather(..., return_exceptions=True)` when you want per-prompt results regardless. Always bound concurrency — unbounded fan-out is how agents blow provider rate limits the hub is trying to manage.

## Typing and tests

pyright strict is the bar; annotate everything public.

```toml
[tool.pyright]
typeCheckingMode = "strict"
pythonVersion = "3.12"
```

pytest conventions: tests in `tests/`, named `test_<module>.py`; parametrize instead of copy-pasting cases; agent contract tests feed canned JSON through `main()` via `capsys`/`monkeypatch` on stdin and assert the stdout document parses as `AgentResponse`. No network in tests — the spoke has no network story anyway.

## Single-file agents: PEP 723

Small agents ship as one self-describing file the hub can run with `uv run agent.py` — no project scaffolding:

```python
# /// script
# requires-python = ">=3.12"
# dependencies = ["pydantic>=2.7"]
# ///
import json, sys
...
```

uv resolves and caches the environment on first run. Use this for agents under ~200 lines; graduate to a full pyproject when they grow tests or shared modules.

## Which LLM to use (via helios-ai / aihub.json)

| Task | Provider | Why |
|---|---|---|
| Agent orchestration logic, prompt design, contract design | anthropic (Claude) | Multi-step reasoning about agent behavior |
| Data-wrangling boilerplate, pandas/parsing glue | openai+codex | Fast mechanical codegen |
| Notebooks, quick throwaway scripts | copilot | Inline completion |
| Local/offline experimentation, air-gapped runs | ollama | No network required |
| Workloads over enterprise/tenant data | azure-foundry | Data residency |

## Reference material

- `references/ml-and-rl.md` — the `[ml]` extra (numpy/scikit-learn) and the
  guard pattern for degrading gracefully without it; numpy/sklearn usage as
  practiced in `src/ai/python/helios_agents/`; the advisory-only RL integration
  lane (Yolkster64/RL fork, `outcomes.jsonl` as dataset seed, and the E28/ltrain
  never-auto-execute rule). Read it before touching `analysis.py`, `textwork.py`,
  the `[ml]` extra, or anything RL-adjacent.
- `references/testing-and-libraries.md` — testing idioms as practiced (dependency-free
  pytest, tmp_path board/run fabrication, subprocess round-trips, the C#-source
  `JsonPropertyName` contract test, determinism rules) and the dependency policy:
  stdlib-only core, the `[ml]`/`dev` extras, deliberate absences, when a new dep is OK.
- `references/parallelization-and-fleets.md` — `PythonInsightsSpoke`'s four-process cap,
  why the spoke never fans out itself (no asyncio/multiprocessing in it — verified),
  the worker-lane claim/lease protocol, the throttle layers, the learn-fleet tandem
  cycle, and an honest multi-modal readiness statement (declared today: nothing).
