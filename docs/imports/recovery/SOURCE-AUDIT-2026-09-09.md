# Recovery source audit — 2026-09-09

The 16 supplied attachments were inspected as untrusted reference material. No
attachment was imported, executed, installed, copied into the repository, or used
as a deployment input. This record preserves source identity and safe reuse intent
without publishing private log contents, account identifiers, or credentials.
Repository authority follows the current `AGENTS.md`: `Yolkster64/helios-platform`.

## Source inventory

Names below are relative to the supplied `project_sources/` directory, outside the
repository. Hashes identify the bytes received; they do not prove upstream
integrity. “AST parses” and “no parse errors” are static syntax observations, not
proof of completeness, safety, or successful execution. Every `.crdownload` remains
an unverified partial-download source even where its PowerShell syntax parses.

| Source | Type / completeness observation | Recovery classification | SHA-256 |
| --- | --- | --- | --- |
| `01-ml_registry.py` | Python · AST parses | 15-profile metadata seed; taxonomy reference | `aa6d7a874b9e185893960f5b75a10c7799646b022e7631e6815c5c8f4dc5dfe7` |
| `02-build_super_outputs.py` | Python · AST parses | Report builder; two supporting modules absent | `0e117eb3a407d2f08fce5a26558181199e969b1a872081b36c55172b960d4c3f` |
| `03-aihub_control_server.py` | Python · AST parses | Prototype HTTP server; recover contracts only | `c0a65a348a9a44dfabec43501d346b0811772954c61747ba812a71e61b297535` |
| `04-deep_engine_fabric.py` | Python · AST parses | Engine catalog and heuristic recommendations | `26246a00e4b6ca23a7d2eff3f4beea8125d446a36fc74ebb1ae8e280c638a116` |
| `05-ai.py` | Python · AST parses | Prototype CLI; reconcile response envelopes | `e3c09a4931031d6ef1b5bdbfca85cc8fbcd894c693b5f142a2bb3dcd57a2bdb9` |
| `06-hermes_xcore_training_loop.py` | Python · AST parses | Stub execution loop; missing Hermes modules | `5534eae4a7ff4fe6f5dfa51358591220177f9a93f9fed0a64252d02efe8dcb48` |
| `07-hermes_xcore_training_loop_pseudo.py` | Python · AST parses | Minimal illustrative dispatcher; missing Hermes modules | `bb772c971d920e3dbab4addb38edba41da39ab0247bcc2cd78acca6606c19000` |
| `08-reboot_needed` | Text marker · 7 bytes | Historical evidence; no current reboot instruction | `b625e5139b05722842537c7016e2e78c22d36212eaeae63fce2b2005b7808f33` |
| `09-01_LocalRepair_20260604_013051.log` | Legacy-encoded text · CRLF | Historical repair evidence; private contents withheld | `11a996fd70aae1101058d589db67988bb31e9c2fbf70f46dcd3e15d6e61d1778` |
| `10-00_Master_20260604_012614.log` | Legacy-encoded text · CRLF | Historical master evidence; private contents withheld | `3b52e341b6af35a4ac7f3675b736da1b24f464f9b1ffc277c7f13aad9f96f2aa` |
| `11-part13_v4-FINAL.txt.crdownload` | PowerShell-like download · 1 parse error | Defer execution; UI/bootstrap/MCP intent only | `1e4ab0eabd609c68263882b2fb2e643493870fcd3b05906cd23589316cf41f76` |
| `12-08_AzureDevStack.ps1-1-.txt.crdownload` | PowerShell download · no parse errors | Defer; cloud setup and machine environment writes | `265c0fbd9bc659ae5802837a6eb68af45fa71cfde225ef9a9cc0b8cf79a9586c` |
| `13-06a_AzureVNet_DNS-1-.txt.crdownload` | PowerShell download · no parse errors | Defer; network and DNS deployment intent | `2b87d47b7628204d35dab1bac5e30378f571e6f7815c733a11da5e9c0c9b37fb` |
| `14-Deploy-WinRE.txt.crdownload` | PowerShell download · no parse errors | Defer; WinRE and scheduled-task operations | `b4c00bb186bdb3832ba0ab3b666ea672b3ff30f31f231eb268049845dfa7d555` |
| `15-03_M365Security.txt.crdownload` | PowerShell-like download · 1 parse error | Defer; tenant/security policy operations | `077e94f7492bb647d119e0fa98b49e1f98f5cee13bb7587c7bcecf5133491f56` |
| `16-06b_KeyVault_PrivateEndpoint.txt.crdownload` | PowerShell download · no parse errors | Defer; vault/network/identity/secret operations | `6209c90733504c4fd7fa15078c5984135717d8dcf255b90bc3410b4610280c1f` |

## Grounded findings

- **Catalogs are metadata, not installed engines.** `01` seeds names, objectives,
  cadences, and backends. `04` selects entries through rules; its
  `expected_memory_efficiency_score` is a formula based on selected metadata,
  not a measured memory benchmark. CUDA labels do not prove GPU availability.
- **The prototype server is unsuitable as the shared gateway.** In `03`, `main`
  defaults to all-interface HTTP binding; `do_POST` performs task/training writes
  without an authentication check. `_read_body` trusts the declared body length,
  and task persistence reads then rewrites one JSON file without locking despite
  using `ThreadingHTTPServer`. Training submission records a queued task and log
  entry; no executing training worker is established by this file.
- **The prototype CLI and server disagree on `/meta`.** `03` wraps metadata in
  `data`, while `05` reads several metadata fields from the outer object. A
  successful HTTP response can therefore produce missing or empty CLI summaries.
  The CLI also accepts a credential in an argument and renders raw error payloads;
  retain its command intent through the current launcher, not that credential flow.
- **Training outcomes are simulated.** `06` calls `_execute_stub`, which derives
  quality and latency from task parameters, then feeds those scores to its history
  and reflection store. Its three-component memory vector is a feature tuple;
  it is not a learned text embedding. `07` is an illustrative zero-vector dispatch.
  Neither file demonstrates a real model-training result or a running fleet.
- **Required implementation is missing from this bundle and checkout.** `02`
  imports `security_optimizer` and `vm_orchestrator`; `06`/`07` import the absent
  `hermes_xcore` orchestration/routing/storage/generation package. Configuration
  and runtime artifacts referenced under the old `x-tier` layout are also absent.
  A parseable Python file cannot supply these missing components.
- **The recovered MCP label overstates its implementation.** `11`'s
  `Start-MCPServer` installs an npm package and writes a tool/resource description;
  it does not start a server or implement handlers for the declared tools. Reuse
  the current C# MCP protocol surface instead of treating that file as a gateway.
- **Cloud and device scripts remain reference-only.** `11`/`12` contain
  machine-scoped environment writes; `13` changes network/DNS resources; `14`
  invokes WinRE modes and registers scheduled tasks; `15` modifies tenant and
  endpoint security; `16` creates vault/network/identity resources and includes
  secret access helpers. None provides authorization to apply those operations.
  PowerShell 7.5.3 static parsing found errors at line 909 of `11` and line 503 of
  `15`; the remaining four downloads parsed. No signature block was found in
  these six source texts. No execution or repair was attempted.

## Reuse through the existing control path

“Current source” below means code present in this checkout. It does not assert
live credentials, workers, transport availability, cloud deployment, or a native
Windows build.

| Recovered intent | Current source / safe integration point | Remaining work |
| --- | --- | --- |
| ML registry and engine taxonomy (`01`, `04`) | `src/ai/python/helios_agents/engines.py` already separates implemented, prototype, and concept entries, with implementation provenance and separate runtime availability. | Add an implementation and meaningful tests before promoting a concept; benchmark performance claims. |
| One CLI and control panel (`03`, `05`) | `scripts/bootstrap/connect.py`, `src/ai/HELIOS.AIHub`, and `src/gui/HELIOS.Shell` provide the shared setup/hub/UI path. | Validate native builds and real provider access; do not revive a second unauthenticated server. |
| Cross-assistant tools and handoffs (`11`) | `src/mcp/HELIOS.Mcp`, `src/mcp/HELIOS.RemoteMcp`, and `HeliosHandoffTools.cs` contain the reviewed protocol and bounded handoff source for this change. | Full package-backed transport/JWT validation and authenticated client receipts remain separate activation gates. |
| Hermes/XCore feedback (`06`, `07`) | `config/fleet/fleet-topology.json`, `FleetPlanService.cs`, `fleet_worker.py`, and `fleet_learning.py` provide advisory planning and recorded lane outcomes. The local worker explicitly identifies itself as a stub; lane data is not provider-quality evidence. | Integrate the missing real worker implementation, validate its boundary, and obtain execution receipts before claiming a live training fleet. |
| Azure identity/network/vault setup (`12`, `13`, `16`) | Repository `infra/` and `scripts/bootstrap/azure-oidc-setup.*` hold the explicit target and `azure-dev` trust path. | Translate reviewed intent into declarative changes and inspect a target-specific plan before any apply. |
| WinRE and M365 recovery (`08`–`10`, `14`, `15`) | Preserve only this source ledger and the existing recovery/security work lanes. | Obtain complete authoritative scripts and device/tenant evidence; do not replay historical logs or partially downloaded commands. |

## Validation receipt

All seven Python sources were parsed with `ast.parse`, without importing them.
All six PowerShell downloads were parsed with
`System.Management.Automation.Language.Parser.ParseFile`, without invocation.
The supplied log texts were classified only; their private contents are not part
of this public record. A reboot marker is historical evidence, not desired state.

Separately, the **current repository's 17 Azure OIDC PowerShell tests passed**
under scratch-installed PowerShell 7.5.3, using an inert Azure CLI. This includes
existing-federation issuer/audience checks and refusal of conflicting trust. That
result validates the maintained bootstrap, not any uploaded recovery script:

```bash
python3 -m unittest scripts.bootstrap.tests.test_azure_oidc_target.AzureOidcPowerShellTests -v
```

The test transcript is retained with the local validation evidence as
`oidc-powershell-final.log`. No Azure login, tenant/RBAC change, secret access,
provider call, disk operation, or deployment was performed by this audit.
