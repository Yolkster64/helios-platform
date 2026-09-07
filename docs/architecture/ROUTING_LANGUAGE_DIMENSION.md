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

`tandem` and `compare` are task-type-only today; they record language-less outcomes.

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
- a language-qualified route learns from records tagged with that language; when none
  exist yet it falls back to the parent task type's language-less records, never to
  another language's.

The scoping is `ChainReorderEngine.ForLanguage`, applied after the advisory-record
exclusion (`OrganicOnly`) that keeps source-tagged records out of routing. The fleet
planner scores pools on language-less evidence for the same reason: pools route by bare
task type. Nothing here changes the advisory contract — recommendations are reported,
never auto-executed.

The Python spoke's `provider_summary` (behind `/v1/insights`) adds a `languages` map —
per-language, per-provider aggregates — only when at least one outcome in the window
carries a language; a window of legacy records summarizes byte-for-byte as before.

## Compatibility summary

- No language given → identical chains, identical outcome JSON, identical learning input.
- Old outcome records → deserialize with `Language = null` and count as language-less.
- `helios_task_routing_get`, `/v1/routing`, and `helios-ai routing` return the whole
  table, qualified keys included; consumers that key on the bare task type can split on
  the first `:` (`TaskTypeRoutingStrategy.SplitRoutingKey`).
