# Python testing & libraries — helios-agents spoke

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.*

Scope: how `src/ai/python` is actually tested, and what it is allowed to depend on.
Companion to `ml-and-rl.md` (the `[ml]` guard pattern lives there — not repeated here).

## The harness: dependency-free pytest

CI runs the suite on a bare interpreter — `cd src/ai/python && python3 -m pytest tests`
(CLAUDE.md "Build & test"). `pytest>=8` is the entire `dev` extra and
`testpaths = ["tests"]` the entire pytest config (`src/ai/python/pyproject.toml`).

No mocking libraries — verified: nothing under `src/ai/python/tests/` imports
`unittest.mock` or `pytest-mock`. The only test double in the suite is pytest's built-in
`monkeypatch`, used solely to `setenv` the `HERMES_KANBAN_*` env contract
(`tests/test_fleet_worker.py`). Everything else runs real code against real files and
real subprocesses. The policy as practiced: when behavior depends on the environment,
inject it through the contract production already has — env vars, file paths, or an
argument like `run_worker(config, stop: threading.Event)` — then exercise the real path.

## tmp_path fabrication: build the world the code expects

Tests fabricate the exact on-disk contracts production consumes, always under `tmp_path`:

- Kanban boards: `_board(tmp_path, tasks)` writes `{"board": ..., "tasks": [...]}` and
  `_config(...)` builds a `WorkerConfig` with fast poll/timeout knobs
  (`tests/test_fleet_worker.py`).
- Whole fleet runs: `_make_run(tmp_path, pools)` builds `.helios/fleet/<runId>/` —
  `manifest.json` (runId, status, `pools` with `board`/`db`/`claimLock`) plus one
  `boards/<board>.json` per pool (`tests/test_fleet_learning.py`).
- Task dicts come from a `_task(...)` helper that reproduces exactly what
  `fleet_worker` stamps on claim and resolve (`assignee`, `runId`, `claimedAt`,
  `resolution`, `finishedAt`, `result`/`reason`) — the fabricator mirrors the writer,
  so fixtures cannot drift from production output shapes.

Failure-path fixtures are fabricated the same way: a torn board is literally a
half-written JSON string (`test_torn_board_read_is_an_idle_poll_not_a_crash`), a stale
lock is a lockfile with its mtime pushed back via `os.utime`, a corrupt dedupe index is
`"{not json"` written over the real one.

## Subprocess round-trips of the `__main__` CLI

The boundary the C# hub calls is tested as a real child process, in both modes
(`tests/test_boundary.py` `_invoke`, `tests/test_fleet_learning.py` `_invoke_cli`):

```python
proc = subprocess.run(
    [sys.executable, "-m", "helios_agents"],          # or + argv for the fleet subcommands
    input=payload, capture_output=True, text=True, cwd=SPOKE_DIR, timeout=60)
```

Idioms that matter: `sys.executable`, never a hardcoded `python3`; `cwd=SPOKE_DIR`
(derived `Path(__file__).resolve().parent.parent`) so `-m helios_agents` resolves with
no install step; a `timeout` so a hung spoke fails the test instead of CI; and
`json.loads(proc.stdout)` as the assertion that stdout carries nothing but the response
document — the stdout-is-the-wire rule tested directly.

## The cross-language contract test (signature idiom)

`tests/test_fleet_learning.py::test_record_field_names_match_csharp_routing_outcome`
keeps the Python-emitted JSONL aligned with the C# reader by parsing the C# source as
the single source of truth instead of duplicating a field list:

```python
source = LEARNING_STORE_CS.read_text(encoding="utf-8")
block = source[source.index("record RoutingOutcome"):source.index("interface ILearningStore")]
csharp_names = re.findall(r'JsonPropertyName\("([^"]+)"\)', block)
assert csharp_names, "RoutingOutcome no longer declares JsonPropertyName attributes"
...
assert list(record.keys()) == csharp_names   # names AND declaration order
```

The pieces that make it robust: slice the source down to the one record so a
`JsonPropertyName` elsewhere in the file cannot leak in; assert the extraction found
anything (silent-regex-rot guard); compare as ordered lists, because
`fleet_learning._record` deliberately mirrors the C# declaration order; and
`pytest.skip` when `LearningStore.cs` is absent (a packaged `python-spoke/` checkout has
no C# tree). Renaming a C# property now fails a Python test instead of silently
producing records `LocalJsonlLearningStore` drops. Use this pattern whenever Python
emits data a C# `JsonPropertyName`-annotated type must read back.

## stdin-JSON boundary tests

`tests/test_boundary.py` pins the envelope the C# side depends on
(`helios_agents/__main__.py`):

- Malformed stdin → `{"ok": false, "error": ...}` and exit 1 — reported, never a
  traceback (`test_malformed_json_is_reported_not_crashed`).
- The unknown-op error names every known op, so the error is self-documenting
  (`test_unknown_op_names_the_known_ops`).
- Argument validation is parametrized and tested in-process via `boundary.run(...)`
  with `pytest.raises(ValueError)` — no subprocess needed for pure validation.
- Every `_OPS` entry is dispatched at least once (`test_run_dispatches_every_op`).
- The argv (fleet CLI) mode has its own error shape — `{"error": ...}`, exit 1, no
  envelope (`test_cli_failure_is_json_error_and_exit_1`).

## Determinism rules

- Backend-membership assertions: `result["backend"] in ("numpy", "pure-python")` /
  `("sklearn", "jaccard")` (`tests/test_analysis.py`, `tests/test_textwork.py`) — every
  test must pass both on an `[ml]` box and a bare one; never assert one backend.
- Fixed stamps: `CLAIMED`/`FINISHED` constants two seconds apart, latency asserted as
  exactly `2000.0` (`tests/test_fleet_learning.py`). No `datetime.now()` in assertions;
  the now-fallback paths are covered by removing stamps instead
  (`test_missing_claim_stamp_yields_zero_latency`).
- Rounding is part of the contract: 4 decimals — `round(blocked / len(rows), 4)`
  (`helios_agents/fleet_learning.py`), asserted as `round(10 / 15, 4)`
  (`tests/test_analysis.py`).
- Timezone honesty: the DST regression test runs a child interpreter with
  `TZ=America/Chicago` and patches `time.time` inside the child, skipping where
  `time.tzset` does not exist (`test_claim_lease_uses_utc_during_daylight_saving_time`)
  — process-local TZ games never contaminate the test process.
- Evidence self-verification: `tests/test_engines.py` asserts every implemented
  engine's `implementation` path is a real file in the repo — the catalog cannot claim
  code that is not checked in.

## Libraries: the stdlib-first rule

The spoke's base install is `dependencies = []` (`src/ai/python/pyproject.toml`), and
that is a contract, not an accident: `PythonInsightsSpoke` launches the spoke as a bare
`python`/`python3 -m helios_agents` subprocess — no uv, no venv, no pip
(`src/ai/HELIOS.AIHub/Learning/PythonInsightsSpoke.cs`) — so every module on a
C#-invoked path must import on a stock interpreter anywhere the hub runs. The pyproject
comment says it outright: "The spoke runs dependency-free anywhere (Cloud Shell,
Codespaces, bare Linux)". `scripts/fleet/learn-fleet.ps1` and `start-fleet.ps1` invoke
it the same bare way.

| Extra | Packages (`src/ai/python/pyproject.toml`) | Consumed by |
|---|---|---|
| `ml` | `numpy>=1.26`, `scikit-learn>=1.4` | `analysis.py`, `textwork.py` (guarded imports) |
| `dev` | `pytest>=8` | `src/ai/python/tests/` |

Deliberately absent from the core (verified by grep over `src/ai/python`):

- **pydantic** — nowhere in the spoke. The SKILL's pydantic v2 patterns are for
  standalone uv-managed agents with their own environments; the shipped spoke validates
  by hand (`__main__.py`'s `_outcomes`/`_texts`/`_bool`/`_path` helpers) precisely so it
  stays import-free.
- **requests** (or any HTTP client) — the hub-and-spoke rule: the spoke has no network
  story at all; the C# hub performs provider calls and passes data in.
- **numpy / scikit-learn in core paths** — the only imports are the guarded ones at
  `helios_agents/analysis.py:14` and `helios_agents/textwork.py:13-14`
  (`ml-and-rl.md` documents the guard pattern).

When a new dependency is justified: it goes into `[ml]` (or a new optional extra),
behind the guard pattern, with the pure-Python fallback returning the same JSON shape —
and never into `engines.py`, `__main__.py`, `fleet_worker.py`, or `fleet_learning.py`,
the modules `PythonInsightsSpoke`, `start-fleet.ps1`, and `learn-fleet.ps1` execute
(`fleet_learning.py`'s docstring pins "stdlib only"). A base dependency would break the
C# spoke on every box that has Python but not that package.
