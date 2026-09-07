# Routing: the language dimension

The hub routes by **task type** (`config/aihub.json` → `routing.taskRouting`). This
document describes the optional second dimension — the **language** of the work — that
lets one task type carry different provider chains for, say, F# than for Python, without
forking every other task type. It complements `MULTI_LLM_INTEGRATION.md`, which stays the
authority on providers, task types, and the learning loop.

## Lookup order

A route request carries a task type and an optional language. The chain is the first of
these that exists and is non-empty:

1. `taskRouting["{taskType}:{language}"]` — the language-qualified chain
2. `taskRouting[taskType]` — the bare task type
3. `routing.defaultChain`

A request with no language skips step 1, so every existing caller behaves exactly as
before. The lookup lives in `TaskTypeRoutingStrategy.GetChain(taskType, language)`
(`src/ai/HELIOS.AIHub/Routing/TaskTypeRoutingStrategy.cs`) and is pinned by
`tests/HELIOS.AIHub.Tests/Routing/TaskTypeRoutingStrategyTests.cs`.

### A qualified key passed as the task type

`helios_task_routing_get`, `/v1/routing`, and `helios-ai routing` list the table's keys
verbatim, so a caller may send `code_generation:fsharp` as the *task type* with no
language. `AIHubService.RouteAsync(HubRouteRequest)` canonicalizes such a request before
the chain lookup, the outcome record, and the learning read: when the task type contains
the separator, `taskRouting` holds that exact key with a non-empty chain, the language
part is already canonical, and the request either carries no language or carries that
same language (after normalization, so `F#` counts), it is split into
(`code_generation`, `fsharp`). The chain served is the one the qualified key names, as
before; what changes is the record — `taskType: code_generation, language: fsharp`, the
same bucket a caller passing the bare task type with `language: fsharp` produces —
instead of a task type `code_generation:fsharp` with no language, a second evidence
bucket the (taskType, language) reads never see. Everything else passes through
unchanged: a bare task type; a qualified-looking key the table does not hold (an ordinary
unknown task type, served by `routing.defaultChain` and recorded verbatim); a key whose
language part is not canonical (`code_generation:F#`, which `GetChain` on the split would
not resolve); and a request whose language contradicts the key's
(`code_generation:fsharp` with `language: cpp`) — the hub cannot tell which half the
caller meant, so it neither guesses nor rejects, and the request is served and recorded
exactly as sent (task type `code_generation:fsharp`, language `cpp`). When the resolved
chain lists no registered provider, the error names the key the lookup stopped at:
`code_generation:fsharp` when that qualified chain is configured, the bare parent when an
explicit language has no qualified chain and the request fell through to the parent's
(naming `code_generation:cobol` there would send the operator to configure a chain the
request never used), and `routing.defaultChain` when neither is configured.

`tandem` applies the same canonicalization to its task type: it takes no language, so
only the no-language case arises. The chain it races is the qualified key's, every
outcome it records lands in the same (taskType, language) bucket a routed request would
write, and the result's `taskType` is the bare task type (the `/v1/tandem` payload gains
no field). The rule is `TaskTypeRoutingStrategy.CanonicalizeTaskType`, pinned by
`TaskTypeRoutingStrategyTests` and `AIHubServiceTests`.

## Language keys and normalization

Language values are normalized before lookup and before recording — trimmed,
lower-cased, a leading extension dot dropped, and common aliases folded — so callers may
pass `F#`, ` cpp `, `.ps1`, or `C++` and still hit the `fsharp`, `cpp`, `powershell`, and
`cpp` chains. Blank input means "no language". Canonical keys used in the shipped config:

| Key | Also accepted |
|---|---|
| `csharp` | `c#`, `cs` |
| `fsharp` | `f#`, `fs` |
| `cpp` | `c++`, `cxx`, `cc` |
| `python` | `py` |
| `powershell` | `ps`, `ps1`, `pwsh` |
| `bicep`, `yaml`, `json` | `yml` → `yaml` |

Configuration keys must use the canonical lower-case form (`code_generation:fsharp`,
never `code_generation:F#`); `ConfigBindingTests` rejects a qualified key whose language
part is not already normalized or whose bare parent task type is missing.

## Shipped chains

`config/aihub.json` and `config/aihub.cloud.json` each carry a small, consistent set of
language-qualified chains built only from providers those files already define:

- `code_generation:cpp`, `code_generation:fsharp`, `code_generation:python`
- `code_review:bicep`, `code_review:powershell`

They differ from their parents only in provider *order and fallbacks* — the same lanes,
promoted or demoted for that language. Adding a chain is a config edit: add the key under
`taskRouting` in both files (the cloud profile uses hosted providers only), keep the
bare parent, and run `dotnet test tests/HELIOS.AIHub.Tests`.

## Surfaces

| Surface | How the language is given |
|---|---|
| CLI | `helios-ai route <task-type> "<prompt>" --language <lang>`; `helios-ai routing` lists qualified chains with a `+` marker |
| REST | `POST /v1/route` body field `language` (optional) |
| MCP | `helios_ai_route` optional `language` parameter |
| Hub API | `AIHubService.RouteAsync(HubRouteRequest)`; the `(taskType, prompt, system)` overload is unchanged |

`tandem` takes a task type and no language: a bare task type records language-less
outcomes, and a qualified key is canonicalized (see above) so its outcomes carry the
key's language. `compare` takes providers, not a task type, and records nothing.

## Outcomes and learning

Every recorded outcome (`.helios/learning/outcomes.jsonl`, Azure Table in `azure`/`hybrid`
mode) carries the normalized language in a `language` property. The property is omitted
when null, so language-less records serialize exactly as they did before the field
existed, and JSONL written before this change deserializes unchanged
(`LocalJsonlLearningStoreTests` pins the round-trip).

Adaptive routing (opt-in via `learning.adaptiveRouting`; off in `config/aihub.json` and
in the C# default) keys its evidence on **(taskType, language)**:

- a language-less route learns from language-less records only — the records its own
  chain produced, which is also every legacy record;
- a language-qualified route learns from records tagged with that language; when that
  scoped window holds no *organic* record — none exist yet, or every record in it is
  advisory (`source` set: absorption benchmarks, fork digests, fleet-lane outcomes) — it
  falls back to the parent task type's language-less records, never to another
  language's.

The scoping happens at the store, on both axes: routing reads
`ILearningStore.GetRecentOrganicForLanguageAsync(taskType, language, window)`, which takes
the history window *after* scoping by language (null language = language-less records
only, otherwise an exact match on the normalized key) *and* by provenance (records without
a `source` only), so neither another language's newest outcomes nor an advisory ingest —
fleet-lane records land under the very task type they describe — can crowd a route's own
organic evidence out of the window. A window scoped afterwards
(`GetRecentForLanguageAsync`, then `OrganicOnly`) would read a key whose newest `window`
records are advisory as "no evidence" while older organic records exist; that plain
language-scoped read stays on the interface for advisory consumers (a per-language
narrative that wants fleet-lane records too) and no routing or planning path calls it —
`/v1/insights` and `/v1/metrics` read `GetRecentAsync` / `GetRecentAllAsync`.
In Azure Table mode the language-less and the organic reads filter client-side (an
absent `Language` or `Source` column cannot be selected by any OData comparison), so
each scoped read examines at most `AzureTableLearningStore.DefaultScanBudget` (2 000)
entities — two service pages — and returns what it found: a partition whose newest
rows are all advisory, or all another language's (a cheap, persistent write path such
as `POST /v1/learning` with the API key), costs a fixed number of pages per route and
reads as thin or no evidence, in which case routing keeps its configured order. Rows
recorded from now on carry an `Organic` boolean (true when `source` is null) so the
organic read can move server-side once every row a deployment cares about has it —
backfill, or wait for the pre-flag rows to age out of the window — because a filter on
the new column would drop the legacy organic rows that lack it.
`ChainReorderEngine.ForLanguage` and `OrganicOnly`
state the same two rules over an in-memory list (`LanguageScopedHistoryTests` pins the
language one). The fleet planner reads the store the same way (`FleetPlanService`, pinned
by `FleetPlanServiceTests`): a pool whose `taskTypes` names a bare task type is scored on
the language-less key, and a window full of language-qualified outcomes — or of the fleet
collector's own lane records — must not make its samples read as "no evidence"; a pool
naming a qualified key (`code_generation:fsharp`, language part
canonical) is scored on that (taskType, language) window first, falling back to the
language-less window when the scoped read holds nothing organic — the hub's own two-step
read — rather than on the orphan `code_generation:fsharp`-with-no-language bucket that
nothing writes to while that qualified chain is configured. A pool may name a qualified
key the routing table does not hold yet: the planner still splits it (it has no table to
consult) and scores it on the parent's evidence through the fallback, while the hub, which
treats an unconfigured key as a literal task type, records such a route verbatim — the
two agree again the moment the chain is configured. Nothing here changes the advisory
contract — recommendations are reported, never auto-executed.

The Python spoke's `provider_summary` (behind `/v1/insights`) adds a `languages` map —
per-language, per-provider aggregates — only when at least one outcome in the window
carries a language; a window of legacy records summarizes byte-for-byte as before.

## Compatibility summary

- No language given → identical chains, identical outcome JSON, identical learning input.
- Old outcome records → deserialize with `Language = null` and count as language-less.
- `helios_task_routing_get`, `/v1/routing`, and `helios-ai routing` return the whole
  table, qualified keys included; consumers that key on the bare task type can split on
  the first `:` (`TaskTypeRoutingStrategy.SplitRoutingKey`), and a qualified key sent
  back as the task type is canonicalized (see "A qualified key passed as the task type").
- `helios-ai route` rejects an option it does not read (`--langauge`, `--provider`) with a
  usage error and a non-zero exit, so a misspelled `--language` can never route silently
  without the language.
