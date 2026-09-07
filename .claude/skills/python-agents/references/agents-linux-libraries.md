# Agents, Linux tooling, and libraries — the Python spoke as shipped

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* Companions: `ml-and-rl.md` (the `[ml]` guard and the advisory RL
lane), `testing-and-libraries.md` (test idioms, the stdlib-first rule),
`parallelization-and-fleets.md` (the four-process cap, why the spoke never fans out,
the claim-lock protocol). This file covers the agent *shapes* that exist, the Linux
process discipline they follow, and the library policy as practiced. System view:
`docs/architecture/AIHUB_LANGUAGE_ROLES.md`.

Ground truth is `src/ai/python/helios_agents/` — `__main__.py`, `analysis.py`,
`textwork.py`, `engines.py`, `fleet_learning.py`, `fleet_worker.py` — and
`src/ai/python/pyproject.toml`.

## Pattern 1 — the op dispatcher (one JSON in, one JSON out)

`__main__.py:59-83` is the whole agent surface: a dict of op name → lambda over the
request. Each op validates its inputs with tiny helpers that raise `ValueError` with the
field name (`_outcomes`, `_texts`, `_bool`, `_path`, `_optional_path`, `:24-56`), and
`main()` wraps everything into `{"ok": true, "result": …}` or
`{"ok": false, "error": …}` with exit 1 (`:132-145`). The C# caller treats any
non-`ok` envelope as `null` insight (`PythonInsightsSpoke.cs:162-167`).

Adding an op is a four-place change: the lambda in `_OPS`, a C# wrapper method in
`PythonInsightsSpoke` (`:58-111`), the REST or MCP door that exposes it
(`ApiEndpoints.cs:126-149,212-266`; `HeliosAiTools.cs:104-163`), and a boundary test
(`tests/test_boundary.py`, which round-trips the real subprocess and asserts unknown ops
name the known ones).

Trap: `bool` is an `int` in Python. `_bool` and `_validate_bool` check
`isinstance(value, bool)` explicitly (`__main__.py:39-43`; `engines.py:319-321`), and
`_validate_recommendation_inputs` rejects `True` where a number is expected
(`engines.py:414-431`) — the boundary test pins both (`tests/test_boundary.py:44-51`).

## Pattern 2 — the fleet worker as a Linux process

`fleet_worker.py` is the one long-running Python process in the repo, and it behaves
like a daemon lane rather than a script:

- **Signals.** `SIGTERM`/`SIGINT` set a `threading.Event`; the poll loop exits 0
  (`:449-455`). Installing a handler can fail off the main thread or on some platforms,
  and that failure is swallowed on purpose (`:453-456`).
- **Owned log sink.** With `--log-file` the worker reopens `sys.stderr` onto a file it
  opened itself, because inherited pipes break when the launcher exits (`:405-413`).
  `start-fleet.ps1` uses this on Windows and `sh -c 'exec … </dev/null >out 2>err'` on
  Unix so each worker owns its descriptors (`CLOUD_SHELL_AND_LOCAL_FLEET.md` "WSL2",
  "Native Windows").
- **Lockfile mutex.** `os.open(..., O_CREAT | O_EXCL | O_WRONLY)` takes the claim lock;
  the payload records `{pid, assignee, lockedAt}`; a stale lock (dead pid via
  `os.kill(pid, 0)`, or age beyond `lock_stale_seconds` where no pid probe exists) is
  broken (`:125-183`). `EPERM` means "exists, owned by someone else" and counts as
  alive (`:132-134`).
- **Atomic saves.** Boards are written to `.tmp` and `os.replace`d so a poller never
  reads a half-written file (`:118-123`); the same idiom protects the collector's index
  (`fleet_learning.py:129-134`).
- **Leases, not ownership.** A claim older than `claim_lease_seconds` (300 s) is
  claimable again, so a crashed lane never strands work (`:83-89`).
- **stdout purity.** Logs go to stderr only; stdout stays silent so launchers can pipe it
  (`:40-43`, `_log` at `:91-96`).
- **Exit codes.** `2` for a missing `HERMES_KANBAN_DB` or a malformed `--enqueue`
  payload, `1` for a failed enqueue, `0` on drain or signal (`:414-445`).

Env contract, exported by `start-fleet.ps1` and mirrored from the Hermes lane spawn:
`HERMES_KANBAN_DB`, `HERMES_KANBAN_TASK`, `HERMES_KANBAN_RUN_ID`,
`HERMES_KANBAN_CLAIM_LOCK`, plus stub-only knobs (`:61-68`). Feed a live board only
through `--enqueue` (`:30-40`).

## Pattern 3 — time handling across the collector

`fleet_learning.py` parses board stamps with `time.strptime` on the fixed UTC format and
`calendar.timegm`, never `time.mktime`, so DST cannot shift a latency (`:72-87`).
Latency is `finishedAt − claimedAt` in ms, or `0.0` when either stamp is missing — a
hand-resolved task records zero, not a guess (`:137-142`). `timestamp` always parses as
a .NET `DateTimeOffset` because it falls back to the claim time and then to now
(`:145-161`).

## Pattern 4 — Linux environments the spoke must run in

| Environment | What is true there | Consequence for Python code |
|---|---|---|
| Azure Cloud Shell, Codespaces | `python3` present, no venv, no Hermes CLI, two cores; workspace mode caps pool sizes (`CLOUD_SHELL_AND_LOCAL_FLEET.md` "What Cloud Shell detection already does") | Dependency-free is mandatory; idle stubs exit on `HERMES_KANBAN_MAX_IDLE_POLLS` |
| WSL2 | Same as Linux; checkout must live on the WSL filesystem — 9P mounts make claim-lock churn an order of magnitude slower (`CLOUD_SHELL_AND_LOCAL_FLEET.md` "WSL2") | Never assume fast `stat`/rename on `/mnt/c` |
| Docker `fleet-stub` profile | Polls `/fleet/board.json` forever, lanes from `FLEET_LANES`, remaps to `FLEET_UID:FLEET_GID` so locks stay writable on both sides (`CLOUD_SHELL_AND_LOCAL_FLEET.md` "Docker") | File permissions are part of the contract |
| CI (`ubuntu-latest`) | `python3 -m pytest tests` with only `pytest` installed (`.github/workflows/absorption-benchmark.yml:51-52`); `HELIOS_REQUIRE_PYTHON_SPOKE=1` makes the C#→Python round-trip a hard failure (`dotnet-build.yml:35`) | A spoke that needs an import beyond stdlib fails the gate |
| The hosted absorption runner | Keyless by design (`contents: read`), the only sanctioned lane for executing an upstream PR's own build code (`absorption-benchmark.yml:23-24,62-67`) | Never write a Python step that expects a secret |

Interpreter selection is the hub's: `python` on Windows, `python3` elsewhere, working
directory the spoke directory or `HELIOS_PYTHON_SPOKE` (`PythonInsightsSpoke.cs:22-28`).

## Pattern 5 — library policy as practiced

`pyproject.toml`: `requires-python = ">=3.10"` (`:9`), `dependencies = []` (`:10`),
extras `ml = ["numpy>=1.26", "scikit-learn>=1.4"]` and `dev = ["pytest>=8"]`
(`:12-16`), `setuptools` build backend (`:1-3`). SKILL.md's `>=3.12` and `uv` sketches
describe standalone agents; the shipped spoke is deliberately older-interpreter-friendly
and bare-`python3`-runnable (SKILL.md "Project layout").

Guarded optional imports are the only pattern for heavier libraries:
`analysis.py:15-18` (`numpy` or pure-Python mean/std, reported as `"backend"`),
`textwork.py:11-16` (`scikit-learn` presence-probed with `find_spec` and imported at its single use site — TF-IDF cosine or Jaccard, with an empty-vocabulary
fallback at `:52-69`). A new dependency must pass the filter in
`testing-and-libraries.md` "Libraries: the stdlib-first rule" and stay out of the
critical path of every op.

Standard-library reliance worth knowing by name: `argparse` (`__main__.py:93-115`),
`json`, `uuid.uuid5` for deterministic outcome ids (`fleet_learning.py:211-214`),
`dataclasses(frozen=True)` for engine specs (`engines.py:27-48`), `re` for tokenizing
(`textwork.py:18`), `signal`/`threading.Event` (`fleet_worker.py`), `calendar`/`time`.

## Pattern 6 — analytics semantics with numbers

`provider_summary` returns per provider `attempts`, `successRate`, `recentSuccessRate`
over the last `RECENT_WINDOW = 5`, `avgLatencyMs`, `latencyStdMs`, `avgCostUsd`,
`totalCostUsd`, and `avgQuality` (`analysis.py:20,54-105`). `detect_drift` flags a
provider only with `attempts >= DRIFT_MIN_ATTEMPTS = 8` and
`|recentSuccessRate − successRate| >= DRIFT_THRESHOLD = 0.25` (`:21-22,108-127`).

Example: ten outcomes for one provider, the first seven successes and the last three
failures. `successRate = 0.7`, `recentSuccessRate` over the last five `= 0.4`, gap
`−0.3`, so the provider is reported `degrading`. Eight successes then two failures
gives `0.8` vs `0.6`, gap `−0.2` — below threshold, no alert. A single bad call never
raises one.

## Pattern 7 — the engine advisory keeps proposals and reality apart

`recommend_engine_mix` (`engines.py:434-569`) selects only `implemented` engines whose
runtime is available in the caller-supplied snapshot, and returns build candidates in a
separate list. Selection rules as coded (`:470-476`): `routing-policy` and
`provider-outcome-analytics` always; `drift-detector` for `hardened`/`paranoid`;
`online-sgd-router` when pressure ≥ 0.25 or fleet size ≥ 36; `cosine-dedup-kernel` and
`utf8-token-estimator` for `performance` or pressure ≥ 0.6. CUDA is caller-declared,
never probed (`:1-7,519`); runtime availability for `cpp` engines comes from
`NativeGate.Available` on the C# side (`PythonInsightsSpoke.cs:77-111`). Nothing here
installs, trains, or executes anything (`HeliosAiTools.cs:123-124`).

## Traps the reviews have caught

- A corrupt collector index must raise, not fall back to empty — an empty fallback would
  re-append every record ever collected (`fleet_learning.py:114-126`).
- Records are appended *before* the index is persisted: a crash between them re-appends
  at most one batch (at-least-once), never loses one (`:219-226`).
- Torn JSONL lines and torn boards are skipped, mirroring the C# reader
  (`fleet_learning.py:236-253`, `fleet_worker` "torn board read is an idle poll").
- The board name is part of the dedupe key because cross-pool handoffs may reuse a task
  id on another board (`fleet_learning.py:43-52`).
- Fleet-lane records carry `provider: "pool:<name>"` and `source: "fleet-lane"`; they
  are advisory by construction and excluded from adaptive routing (`:16-41`).

## When to route this work to which model or provider

Chains are `config/aihub.json:97-215`.

| Python work | Task type → chain | Why |
|---|---|---|
| Agent contract or prompt design, a new op's semantics | `architecture_design` → `anthropic`, `anthropic-foundry`, `openai` | Multi-step reasoning about behavior (SKILL.md "Which LLM") |
| Parsing glue, JSONL readers, argparse plumbing | `code_generation` → `codex`, `openai-codex`, `openai`, `azure-openai`, `anthropic` | Mechanical; reconcile against Pattern 1 before committing |
| Test scaffolds for a new op | `test_creation` → `codex`, `openai-codex`, `openai`, `anthropic` | Feed canned JSON through `main()` |
| Many similar classifications or summaries over outcomes | `bulk_processing` → `github-models`, `azure-openai`, `ollama` | Cheap, non-agentic |
| Air-gapped runs | `offline` → `ollama` | No network |
| Anything over tenant data | `enterprise_data` → `azure-foundry`, `anthropic-foundry`, `azure-openai` | Data residency |

Language-qualified keys landed in PR #248 (`docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`).
The shipped Python chain is `code_generation:python` → `codex`, `openai-codex`, `openai`,
`github-models`, `azure-openai` (`config/aihub.json:119-125`), selected by
`helios-ai route code_generation "<prompt>" --language python` (`py` normalizes to
`python`: `TaskTypeRoutingStrategy.NormalizeLanguage`,
`src/ai/HELIOS.AIHub/Routing/TaskTypeRoutingStrategy.cs:67-80`). `code_review:python` is
not configured, so `--language python` on a review runs the bare `code_review` chain and
tags the outcome `language: python` for `(taskType, language)` learning
(`ChainReorderEngine.ForLanguage`, `src/ai/HELIOS.AIHub/Learning/ChainReorderEngine.cs:49-62`).
The `python-reviewer` agent is under `.claude/agents/python-reviewer.md` and rostered in
`config/fleet/fleet-topology.json` (`xcore-9-code`, `xcore-9-review`); on the spoke side,
`provider_summary` adds a per-language `languages` map to `/v1/insights` once any outcome
in the window carries a language (`analysis.py:80-105`).
