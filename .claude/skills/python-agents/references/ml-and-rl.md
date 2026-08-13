# ML and RL toolkit reference — helios-agents spoke

Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them. Paths are helios-platform-relative unless prefixed `RL/`, which
means the owner's fork checkout `Yolkster64/RL` (a separate repo, not vendored here).

## What the `[ml]` extra pulls in

The spoke's base install is dependency-free (`dependencies = []`); extras swap
pure-Python math for real libraries when present (`src/ai/python/pyproject.toml`).

| Extra | Packages | Consumed by |
|---|---|---|
| `ml` | `numpy>=1.26`, `scikit-learn>=1.4` | `helios_agents/analysis.py`, `helios_agents/textwork.py` |
| `dev` | `pytest>=8` | `src/ai/python/tests/` |

`helios_agents/engines.py`, `__main__.py`, and `fleet_worker.py` are deliberately
dependency-free — never add an import that would make the `engine_catalog` /
`recommend_engines` ops require the extra.

## Graceful degradation: the guard pattern

Guard the import at module top, keep a module-level flag or aliased `None`, and
report which path ran (`src/ai/python/helios_agents/analysis.py`,
`src/ai/python/helios_agents/textwork.py`):

```python
try:
    import numpy as _np
except ImportError:  # pragma: no cover - exercised on bare interpreters
    _np = None
```

| Module | Optional lib | With lib | Without lib | Reported as |
|---|---|---|---|---|
| `analysis.py` | numpy | `_np.mean` / `_np.std` | `sum/len` mean, population std | `"backend": "numpy" \| "pure-python"` |
| `textwork.py` | scikit-learn | `TfidfVectorizer` + `cosine_similarity` | Jaccard token overlap | `"backend": "sklearn" \| "jaccard"` |

Rules as practiced:

- The pure-Python path is the spec; the library path is an accelerator. Both must
  return the same JSON shape — only the `backend` field may differ. Tests assert
  membership in both values (`src/ai/python/tests/test_analysis.py`).
- Match library defaults deliberately: `analysis._std` divides by `len(values)`
  (population std) precisely because `numpy.std` defaults to `ddof=0`. Changing one
  side silently desynchronizes environments.
- Catch the library's data-shaped failures and fall back, don't crash:
  `textwork._similarity_matrix` catches `ValueError` (empty TF-IDF vocabulary — no
  token of 2+ chars) and drops to Jaccard.

Pitfall: the two textwork backends do not tokenize identically. The sklearn path
feeds lowercased raw text to `TfidfVectorizer(token_pattern=_TOKEN.pattern)` with no
stopword removal; the Jaccard path filters `_STOPWORDS`. Near the `group_similar`
threshold (default 0.6), grouping can differ between an `[ml]` box and a bare one —
treat grouping output as advisory, never as a stable key.

Pitfall: outcomes handed to `provider_summary` / `detect_drift` must be
chronological, oldest first — `RECENT_WINDOW = 5` reads the tail
(`analysis.py`; enforced only by docstring, the code cannot detect misordering).

## RL integration lane (advisory-only experiment bed)

Designation: the owner's fork `Yolkster64/RL` (origin per its `.git/config`;
NVIDIA-NeMo/RL lineage per `RL/README.md`) is the experiment bed for
routing-outcome RL. It is a NeMo-RL post-training toolkit: GRPO, DPO, and SFT built
on Ray and PyTorch (FSDP2 / Megatron-Core) (`RL/CLAUDE.md`). Nothing in
helios-platform imports, vendors, or executes it.

| Concept | Fork evidence (relative to the Yolkster64/RL checkout) |
|---|---|
| GRPO (clipped-PG loss, advantage estimators) | `nemo_rl/algorithms/grpo.py` (`GRPOAdvantageEstimator`, `ClippedPGLossFn`) |
| DPO (preference pairs) | `nemo_rl/algorithms/dpo.py` (`DPOLossFn`, `preference_collate_fn`) |
| SFT (NLL loss) | `nemo_rl/algorithms/sft.py` (`NLLLossFn`) |
| Ray-based scaling | `RayVirtualCluster` imported by all three; `ray[default]==2.54.0` in `RL/pyproject.toml` |
| Runtime floor | `requires-python = ">=3.12"`, `torch==2.10.0` (`RL/pyproject.toml`) — heavier than the spoke's `>=3.10` |

Dataset seed: the learning store's `outcomes.jsonl`.

- Location and gating: `learning.localPath = .helios/learning/outcomes.jsonl`,
  `enabled: false` by default, `historyWindow: 200` (`config/aihub.json`).
- Record shape: `RoutingOutcome` — `timestamp`, `taskType`, `provider`, `model`,
  `success`, `latencyMs`, `costUsd`, nullable `quality` (judge/human rating in
  [0,1]), nullable `pool`, nullable `source`
  (`src/ai/HELIOS.AIHub/Learning/LearningStore.cs`).
- Format: append-only JSONL, one outcome per line, writes serialized through a
  semaphore (`LocalJsonlLearningStore`, same file) — read it as a stream, tolerate
  at most one truncated final line.
- Frame the RL problem as: state = task type + recent provider stats, action =
  provider choice, reward = `success`/`quality`/`costUsd`/`latencyMs` blend. Rows
  with non-null `source` are ADVISORY ingests ("absorption-benchmark",
  "fork-observation"); adaptive routing already excludes them
  (`LearningStore.cs` doc comment) — exclude them from reward signals too.

Hard rule — training never auto-executes. `docs/architecture/ABSORPTION_LEDGER.md`
E28 ("ltrain local training entrypoint", PR #87) records the carve-out: training
runtimes are evaluate-carefully per repo policy; the entrypoint is cataloged as an
advisory engine candidate and nothing more — "advisory catalog only, never
auto-execute". The enforcement mechanism already exists in
`src/ai/python/helios_agents/engines.py`: prototype/concept entries never cross
into `selected_engines`, and `recommend_engine_mix`'s rationale states candidates
"are never invoked by this recommendation". Any RL experiment therefore runs in the
fork checkout, by hand; its trained artifacts re-enter HELIOS only as data
(advisory outcomes with a `source`, or a catalog candidate entry), never as a
process the hub spawns. The spoke's only execution path is
`python -m helios_agents` under `PythonInsightsSpoke`'s four-process cap
(`src/ai/HELIOS.AIHub/Learning/PythonInsightsSpoke.cs`) — do not add a training op
to `__main__.py`'s `_OPS`.

## Not in the repo (candidates)

Nothing below is a helios-platform dependency; adding any of them to the spoke's
base `dependencies` or to `[ml]` is a design decision, not a routine bump.

| Candidate | Where it lives today | Status |
|---|---|---|
| `torch==2.10.0`, `ray[default]==2.54.0`, `transformers==5.3.0` | `RL/pyproject.toml` | Fork-only; far exceeds the spoke's dependency-free contract |
| GRPO/DPO/SFT training runs over `outcomes.jsonl` | fork checkout, manual | Experiment bed only; results return as advisory data (E28) |
| `contextual-bandit-router` and other prototype/concept engines | `engines.py` catalog entries | Advisory candidates; need implementation + tests before `implemented` |
