# Combo calculus — the optimization the hub implements, from the code that exists

*Versions and API claims mirror the cited repo files; update this file in the same PR
that changes them.* Every formula below is quoted from `src/ai/HELIOS.AIHub.Domain/*.fs`,
`src/ai/HELIOS.AIHub.Native/helios_aihub_native.cpp`, or
`src/ai/HELIOS.AIHub/Learning/*.cs`; every number in the worked examples was produced by
running that arithmetic on the stated fixture. Where the code has no formula (prices,
quality judges, a language dimension), the gap is labelled.

## 1. The problem, stated

**Objective.** For a task type `T`, order the operator's configured chain so that the
first provider tried maximizes an evidence-weighted score in which success dominates and
cost and latency are secondary:

```text
maximize   score(p) = wS·successRate(p) + wQ·quality(p) + wL·latencyTerm(p) + wC·costTerm(p)
           with (wS, wQ, wL, wC) = (0.55, 0.25, 0.10, 0.10)          -- RoutingPolicy.fs:48-49
subject to the order being a permutation of the configured chain     -- RoutingPolicy.fs:99-104
```

The weights "favor correctness, because a cheap wrong answer costs more than an
expensive right one" (`RoutingPolicy.fs:40-41`). Cost is therefore *not* the objective;
it is a 10 % tie-breaker among providers that succeed.

**Decision variables** (what the hub, or the operator, actually chooses):

| Variable | Set by | Where |
|---|---|---|
| Chain order for `T` | Learned reorder over organic history, else the configured order | `AIHub.cs:261-328`; `ChainReorderEngine.cs:81-99` |
| Fan-out: sequential (`route`), all-at-once (`tandem`), or ad hoc (`compare`) | The caller's command | `AIHub.cs:171,747,712` |
| Local-first | The operator's chains (`offline → ollama`; `ollama` terminal in `defaultChain`, `bulk_processing`, `general_query`) | `config/aihub.json:87-96,201-214` |
| Catalog pick under a stated preference | `ModelSelection.rank` over Ready providers only | `ModelSelection.fs:75-97`; `AIHub.cs:138-149` |
| Language-qualified chain | The caller's `--language` / `language` (PR #248): `taskRouting["<taskType>:<language>"]` when configured, else the bare task type, else `defaultChain`; the language is normalized first; learning history is scoped to `(taskType, language)`, falling back to the language-less parent records — `docs/architecture/ROUTING_LANGUAGE_DIMENSION.md` | `TaskTypeRoutingStrategy.cs:67-80,168-196`; `ChainReorderEngine.cs:49-62,69-70`; `LearningStore.cs:35-37`; `Program.cs:98-105` |

**Constraints:**

| Constraint | Rule | Where |
|---|---|---|
| Context budget | Drop chain entries whose window cannot fit `promptTokens`; never return an empty chain | `ContextBudget.fs:41-58`; `AIHub.cs:341-390` |
| Readiness | Only `Ready` providers are selectable; Unconfigured is a state with a hint | `TaskTypeRoutingStrategy.cs:140-148`; `ProviderFactory.cs:12-15` |
| Circuit breaker | A provider with an open circuit is skipped with reason `circuit open`; 5 consecutive failures open it for 60 s | `FallbackChain.cs:72-78`; `CircuitBreaker.cs:28-37` |
| Evidence floor | Fewer than 5 attempts ⇒ the provider keeps its configured slot; fewer than 2 confident providers ⇒ no reorder at all | `RoutingPolicy.fs:51-52,117-118` |
| Organic history only | Records with a non-null `source` never influence order | `ChainReorderEngine.cs:25-37` |
| Advisory only | `adaptiveRouting` is `false` in the shipped profile; `fleet-plan` and engine plans report and never apply | `config/aihub.json:218-223`; `FleetPlanService.cs:49-52` |
| Window | At most `historyWindow` (200) newest outcomes per (task type, language) key feed a decision | `config/aihub.json:224`; `AIHub.cs:252-273` |

## 2. The update rules, quoted

### 2.1 Aggregation and the linear score (F#)

`RoutingPolicy.aggregate` folds outcomes for one task type into per-provider
`{Attempts, Successes, MeanLatencyMs, MeanCostUsd, MeanQuality}` (`RoutingPolicy.fs:60-73`).
Then (`RoutingPolicy.fs:78-97`):

```text
inverseNormalized(values, v) = 1                                  if values = [] or max−min < 1e-9
                             = 1 − (v − min(values)) / (max(values) − min(values))   otherwise

score = 0.55 · successRate
      + 0.25 · (MeanQuality if rated, else successRate)
      + 0.10 · inverseNormalized(all MeanLatencyMs, MeanLatencyMs)
      + 0.10 · inverseNormalized(all MeanCostUsd,   MeanCostUsd)
```

`all` is the list of *confident* providers' stats, not every provider
(`RoutingPolicy.fs:120-123`). `reorderChain` ranks the confident set by `score`
descending and splices it back into the configured slots (`RoutingPolicy.fs:126-135`).

### 2.2 Feature engineering and fusion (F#)

For the MLP, each provider's running state becomes six features
(`LearnerFusion.fs:97-113`):

```text
f = [ successRate,
      inverseNormalized(latencyLo, latencyHi, meanLatency),      -- clamped to [0,1], LearnerFusion.fs:92-95
      inverseNormalized(costLo,    costHi,    meanCost),
      quality (or successRate when unrated),
      attempts / (attempts + 5),                                  -- saturating evidence mass
      successRate over the newest 3 outcomes ]                    -- recentWindow = 3
```

Training pairs are prequential: each outcome is predicted from the provider's state
*before* it, so a provider's first outcome yields no sample (`LearnerFusion.fs:138-152`).
Targets (`LearnerFusion.fs:118-122`):

```text
target(success, quality) = s                        when unrated,  s ∈ {0, 1}
                         = 0.5·s + 0.5·clamp01(q)   when rated
```

Fusion (`LearnerFusion.fs:192-224`):

```text
w(attempts) = 0                                   if attempts < 5
            = 0.5 · attempts / (attempts + 10)    otherwise            -- never above 0.5
fused(p)    = (1 − w) · score(p) + w · mlpPrediction(p)
```

### 2.3 The online-SGD learner (C++)

Network: one hidden layer, `tanh` hidden, sigmoid output; weights flat as
`W1[hidden][dim], b1[hidden], W2[hidden], b2` (`helios_aihub_native.h:78-96`). The hub
uses `dim = 6`, `hidden = 16`, 300 epochs, learning rate 0.05, L2 `1e-4`, seed 42, and
requires ≥ 12 training samples (`NeuralRoutingLearner.cs:21-30`).

Forward (`helios_aihub_native.cpp:93-110`):

```text
h_j = tanh( b1_j + Σ_d W1[j][d] · x_d )
p   = σ( b2 + Σ_j W2_j · h_j ),   σ(z) = 1/(1+e^{−z}) computed branch-on-sign  -- :62-69
```

One SGD step per sample (`helios_aihub_native.cpp:336-376`), with `t` clamped to `[0,1]`
and `p` clamped to `[1e-12, 1−1e-12]` before the log:

```text
loss     += −( t·ln p + (1−t)·ln(1−p) )
δ_out     = p − t                                     -- sigmoid + cross-entropy collapse, :351-352
for each hidden j (reading the OLD W2_j first, :354-357):
    grad_W2_j = δ_out · h_j + λ · W2_j
    δ_j       = δ_out · W2_j · (1 − h_j²)
    W2_j     -= η · grad_W2_j
    W1[j][d] -= η · ( δ_j · x_d + λ · W1[j][d] )      for each d
    b1_j     -= η · δ_j                               -- no L2 on biases, :370-372
b2 -= η · δ_out
```

Determinism: xorshift64\* initialization with seed 0 remapped, samples consumed in
caller order, no shuffle (`helios_aihub_native.cpp:42-60`; `helios_aihub_native.h:92-95`).

### 2.4 The cosine kernel and the dedup gate (C++ and C#)

```text
cos(a, b) = Σ a_i·b_i / ( √Σ a_i² · √Σ b_i² ),   0 when the denominator < 1e-12   -- :120-145 (double accumulation)
```

`CompareAsync` hashes each reply into a 64-bucket, L2-normalized word-frequency vector,
computes the pairwise matrix natively, and flags `result_i` as a duplicate of the
earliest `result_j` when `cos ≥ 0.90` **and** token-set Jaccard `≥ 0.5` — the Jaccard
check exists because short unrelated replies can collide into identical hashed vectors
(`AIHub.cs:480-500,509-566`).

### 2.5 Cost and context (F#)

```text
costUsd(rate, usage) = inputTokens/1e6 · inputPerMillion + outputTokens/1e6 · outputPerMillion   -- Pricing.fs:43-49
fits(promptTokens, window) = promptTokens ≤ maxContextTokens − reservedOutputTokens               -- ContextBudget.fs:35-44
reservedOutputTokens = min(4096, contextTokens / 4)                                             -- AIHub.cs:426
promptTokens ≈ asciiChars / 3.85 + multibyteChars   (min 1)                                     -- helios_aihub_native.cpp:19-22,206-208
```

`EstimateCostUsd` returns `0` without reported usage or a confident catalog match
(`AIHub.cs:688-709`); `filterFits` hands back the full chain when nothing fits
(`ContextBudget.fs:50-58`).

### 2.6 The outcome record (the data every rule reads)

`RoutingOutcome` (`LearningStore.cs:8-74`): `outcomeId`, `timestamp`, `taskType`,
`provider`, `model`, `success`, `latencyMs`, `costUsd`, `quality` (nullable `[0,1]`),
`pool`, `source`. No token counts, no language (both are the labelled gaps).

## 3. Worked example A — the linear reorder on twelve outcomes

Fixture, chronological, task `code_generation`, configured chain
`codex → openai-codex → openai → azure-openai → anthropic` (`config/aihub.json:98-104`).
Costs come from the catalog priors and the usage shapes below; `codex` is a CLI agent
and records `0`:

| # | provider | success | latencyMs | costUsd |
|---|---|---|---|---|
| 1 | codex | yes | 42000 | 0 |
| 2 | openai-codex | yes | 9000 | 0.01575 (3000 in / 1200 out at 1.25 / 10) |
| 3 | codex | yes | 38000 | 0 |
| 4 | openai-codex | yes | 11000 | 0.01700 |
| 5 | codex | no | 60000 | 0 |
| 6 | openai | yes | 7000 | 0.00275 (3000 / 1000 at 0.25 / 2) |
| 7 | openai-codex | yes | 8500 | 0.01450 |
| 8 | codex | yes | 45000 | 0 |
| 9 | openai-codex | yes | 12000 | 0.01825 |
| 10 | codex | yes | 40000 | 0 |
| 11 | openai-codex | yes | 9500 | 0.01600 |
| 12 | codex | no | 61000 | 0 |

Aggregate (`RoutingPolicy.aggregate`):

| provider | attempts | successes | mean latency | mean cost |
|---|---|---|---|---|
| codex | 6 | 4 | 47 666.67 ms | 0.0 |
| openai-codex | 5 | 5 | 10 000 ms | 0.0163 |
| openai | 1 | 1 | 7 000 ms | 0.00275 |

Confident set (≥ 5 attempts): `codex`, `openai-codex`; `openai` keeps slot 3.
Normalization uses only the confident pair: latencies `{47 666.67, 10 000}`, costs
`{0, 0.0163}`.

```text
score(codex)        = 0.55·0.6667 + 0.25·0.6667 + 0.10·0.0 + 0.10·1.0 = 0.6333
score(openai-codex) = 0.55·1.0    + 0.25·1.0    + 0.10·1.0 + 0.10·0.0 = 0.9000
```

Reordered chain: `openai-codex → codex → openai → azure-openai → anthropic`.
`explain` would print
`Reordered codex→openai-codex→… -> openai-codex→codex→… (codex 4/6 ok, openai-codex 5/5 ok)`.

What the numbers teach: the CLI agent's unmeasured cost gives it the full 0.10 cost
term, yet it still loses on the 0.55 + 0.25 success/quality terms and the latency term —
cost is a tie-breaker by construction.

## 4. Worked example B — features, fusion, and why the neural path abstains here

Global ranges over all twelve outcomes: latency `[7000, 61000]`, cost `[0, 0.01825]`
(`LearnerFusion.contextOf`). Final-state features (`featuresOf`):

| provider | successRate | latency norm | cost norm | quality | evidence | recent(3) |
|---|---|---|---|---|---|---|
| codex | 0.6667 | 0.2469 | 1.0 | 0.6667 | 0.5455 | 0.6667 |
| openai-codex | 1.0 | 0.9444 | 0.1068 | 1.0 | 0.5 | 1.0 |
| openai | 1.0 | 1.0 | 0.8493 | 1.0 | 0.1667 | 1.0 |

`mlpWeight(6) = 0.5·6/16 = 0.1875`, `mlpWeight(5) = 0.5·5/15 = 0.1667`,
`mlpWeight(1) = 0`. With hypothetical predictions 0.55 (codex) and 0.92 (openai-codex):

```text
fused(codex)        = 0.8125·0.6333 + 0.1875·0.55 = 0.6177
fused(openai-codex) = 0.8333·0.9000 + 0.1667·0.92 = 0.9033
```

But in the real hub this fixture never reaches the MLP: prequential training skips each
provider's first outcome, so 12 outcomes over 3 providers yield 9 samples, below
`MinTrainingSamples = 12`; `NeuralRoutingLearner.Reorder` returns `null` and the engine
reports `linear` (`NeuralRoutingLearner.cs:29-30,134-139`). Rule of thumb: the neural
path needs at least `12 + (providers with history)` organic outcomes for the task type
inside the window, plus the native library on the path.

Targets for the record: `target(true, none) = 1.0`, `target(true, 0.6) = 0.8`,
`target(false, 0.9) = 0.45`.

## 5. Worked example C — one SGD step, by hand

Toy shape allowed by the ABI (`dim = 2`, `hidden = 2`), `η = 0.05`, `λ = 0`, one sample
`x = (0.8, 0.6)`, `t = 1`, weights `W1 = [[0.5, −0.25], [0.1, 0.3]]`, `b1 = [0, 0]`,
`W2 = [0.4, −0.2]`, `b2 = 0`:

```text
h = [tanh(0.25), tanh(0.26)] = [0.244919, 0.254296]
z = 0.4·0.244919 − 0.2·0.254296 = 0.047108      p = σ(z) = 0.511775
loss = −ln 0.511775 = 0.669870                   δ_out = p − t = −0.488225
unit 0: grad_W2 = −0.119575   δ_h = −0.488225·0.4·(1 − 0.244919²) = −0.183576
unit 1: grad_W2 = −0.124153   δ_h = −0.488225·(−0.2)·(1 − 0.254296²) = 0.091331
W2' = [0.405979, −0.193792]
W1' = [[0.507343, −0.244493], [0.096347, 0.297260]]
b1' = [0.009179, −0.004567]        b2' = 0.024411
```

Every update moves `p` toward `t = 1` (the second unit's negative `W2` makes its hidden
delta positive, so it pushes `h_1` *down*). The shipped shape has `16·(6+2)+1 = 129`
weights (`helios_aihub_native.cpp:81`).

## 6. Worked example D — context budget and the dedup gate

A 250,000-token prompt with the catalog windows and `reserved = min(4096, window/4)`:

| provider | window | reserved | capacity | fits |
|---|---|---|---|---|
| anthropic (`claude-sonnet-5`) | 1,000,000 | 4,096 | 995,904 | yes |
| openai (`gpt-5-mini`) | 400,000 | 4,096 | 395,904 | yes |
| github-models | 128,000 | 4,096 | 123,904 | no |
| ollama | 128,000 | 4,096 | 123,904 | no |

So `documentation_generation` (`anthropic → anthropic-foundry → openai → github-models`)
becomes `anthropic → anthropic-foundry → openai` for that prompt; `anthropic-foundry`
passes through because it has no catalog window. Token estimates behind this:
`"Hello, world"` → 12 ASCII bytes / 3.85 = 3.12 → 3 tokens; four CJK characters → 4
tokens; a 62-byte English sentence → 16 tokens.

Dedup: `cos([1,1,0,1], [1,1,1,0]) = 2/3 = 0.667` — below 0.90, not a duplicate. A
4-bucket toy where `advances` and `skips` collide into the same bucket gives
`cos = 1.0` and Jaccard `3/5 = 0.6 ≥ 0.5`, so the pair *would* be flagged — the real
64-bucket vector makes such collisions rare, and the Jaccard verify is the second gate
(`AIHub.cs:549-556`).

## 7. Worked example E — the catalog pick under each preference

Candidates for `code_generation` in `config/model-catalog.json`: `gpt-5.4`
(frontier, medium, 10 + 30 = 40) and `gpt-5.1-codex-max` (specialist, medium,
1.25 + 10 = 11.25).

| Preference | Key (`ModelSelection.rank`) | Winner |
|---|---|---|
| cost | `(estimatedCost, speedRank, classRank)` = (11.25, 1, 1) vs (40, 1, 0) | `gpt-5.1-codex-max` |
| latency | `(speedRank, estimatedCost)` = (1, 11.25) vs (1, 40) | `gpt-5.1-codex-max` |
| quality | `(classRank, −context)` = (1, −400000) vs (0, −400000) | `gpt-5.4` |
| balanced | `0.4·normCost + 0.3·speed/2 + 0.3·class/2` = 0.30 vs 0.55 (lower wins) | `gpt-5.1-codex-max` |

Both rows belong to provider `openai`, so `--optimize … --for code_generation` sends
the request to `openai` with the winning model as the override
(`Program.cs:62-70`).

## 8. Decision rules that follow from the math

| Question | Answer from the code |
|---|---|
| When does `tandem` beat `route`? | When two chain members differ in kind (API vs CLI) and you need evidence: tandem records every provider's outcome, so 5 tandem runs cross the confidence floor for the whole chain at once, where `route` records only the providers it reached. Cost: every provider in the chain per run (`AIHub.cs:764-769`) |
| When does `compare` earn its tokens? | When disagreement is the signal — an architecture or security decision — because it records nothing and reorders nothing (`AIHub.cs:712-728`; no task type, no `RecordOutcomeAsync`). Never for bulk |
| When does learning change anything? | Only with `adaptiveRouting: true`, ≥ 5 organic attempts on ≥ 2 chain providers, within the window; and the neural blend only above 12 prequential samples with the native library present |
| Why is a free-looking provider not always first? | Cost is 0.10 of the score and normalized against peers; a `0` cost buys at most 0.10, while a failure costs 0.55 + 0.25 |
| What does a language dimension change? | Which chain is scored and which history scores it, not the formula: `route … --language fsharp` selects `code_generation:fsharp` when configured, and `ChainReorderEngine.ForLanguage` (`ChainReorderEngine.cs:49-62`) feeds the learner only records tagged `fsharp` (falling back to the language-less parent records, never to another language's), so `code_generation:fsharp` learns independently of `code_generation:csharp`; a language-less route sees only language-less records, exactly as before PR #248 (`docs/architecture/ROUTING_LANGUAGE_DIMENSION.md`) |
| Where is a price a fact? | Nowhere in the hub's decisions: catalog rates are priors; recorded `costUsd` is the measurement; a pricing block in `config/aihub.json` is a labelled proposal (`references/model-strengths-and-cost.md`) |

## 9. Reproducing the numbers

Every value above is reproducible by hand from the quoted formulas or by replaying the
fixture through the real interop: `RoutingPolicyInterop.ReorderChain` and
`LearnerFusionInterop.BuildCandidates` accept exactly the parallel arrays shown
(`RoutingPolicy.fs:159-181`; `LearnerFusion.fs:276-285`), and
`PricingInterop.EstimateCostUsd(3.0, 15.0, 1_000_000, 1_000_000) = 18.0` is already a
repo test (`tests/HELIOS.AIHub.Tests/Learning/RoutingPolicyInteropTests.cs:57-62`). A
mismatch between this file and a fresh replay is a bug in this file.
