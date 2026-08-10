# Recovered AI Engine Fabric — Integration Record

This record governs the August 2026 recovery bundle supplied for the Yolkster-owned
platform. The target is `Yolkster64/helios-platform`; no M0nado branch is an authority for
this integration.

## Decision

The bundle is evidence and design vocabulary, not a deployable runtime. Its useful engine
taxonomy is rewritten behind the existing C# orchestration → Python spoke boundary. Raw
HTTP servers, synthetic "training," workstation repair logs, and broad Azure/Microsoft 365
mutation scripts are excluded from the runnable tree.

The source bytes are intentionally not committed. These SHA-256 identities make the audit
reproducible without publishing machine logs or unsafe scripts:

| Source | SHA-256 |
|---|---|
| `ml_registry.py` | `aa6d7a874b9e185893960f5b75a10c7799646b022e7631e6815c5c8f4dc5dfe7` |
| `build_super_outputs.py` | `0e117eb3a407d2f08fce5a26558181199e969b1a872081b36c55172b960d4c3f` |
| `aihub_control_server.py` | `c0a65a348a9a44dfabec43501d346b0811772954c61747ba812a71e61b297535` |
| `deep_engine_fabric.py` | `26246a00e4b6ca23a7d2eff3f4beea8125d446a36fc74ebb1ae8e280c638a116` |
| `ai.py` | `e3c09a4931031d6ef1b5bdbfca85cc8fbcd894c693b5f142a2bb3dcd57a2bdb9` |
| `hermes_xcore_training_loop.py` | `5534eae4a7ff4fe6f5dfa51358591220177f9a93f9fed0a64252d02efe8dcb48` |
| `hermes_xcore_training_loop_pseudo.py` | `bb772c971d920e3dbab4addb38edba41da39ab0247bcc2cd78acca6606c19000` |
| `.reboot_needed` | `b625e5139b05722842537c7016e2e78c22d36212eaeae63fce2b2005b7808f33` |
| `01_LocalRepair_20260604_013051.log` | `11a996fd70aae1101058d589db67988bb31e9c2fbf70f46dcd3e15d6e61d1778` |
| `00_Master_20260604_012614.log` | `3b52e341b6af35a4ac7f3675b736da1b24f464f9b1ffc277c7f13aad9f96f2aa` |
| `part13_v4-FINAL.txt.crdownload` | `1e4ab0eabd609c68263882b2fb2e643493870fcd3b05906cd23589316cf41f76` |
| `08_AzureDevStack.ps1 (1).txt.crdownload` | `265c0fbd9bc659ae5802837a6eb68af45fa71cfde225ef9a9cc0b8cf79a9586c` |
| `06a_AzureVNet_DNS (1).txt.crdownload` | `2b87d47b7628204d35dab1bac5e30378f571e6f7815c733a11da5e9c0c9b37fb` |
| `Deploy-WinRE.txt.crdownload` | `b4c00bb186bdb3832ba0ab3b666ea672b3ff30f31f231eb268049845dfa7d555` |
| `03_M365Security.txt.crdownload` | `077e94f7492bb647d119e0fa98b49e1f98f5cee13bb7587c7bcecf5133491f56` |
| `06b_KeyVault_PrivateEndpoint.txt.crdownload` | `6209c90733504c4fd7fa15078c5984135717d8dcf255b90bc3410b4610280c1f` |

| Recovered material | Decision | Replacement in this repository |
|---|---|---|
| `ml_registry.py`, `deep_engine_fabric.py` | Rewrite taxonomy; default imported entries to prototype/concept | `src/ai/python/helios_agents/engines.py` |
| `build_super_outputs.py` | Reject missing-module artifact generator | Typed config, API, CLI, and MCP responses |
| `aihub_control_server.py` | Reject unauthenticated `0.0.0.0` threaded writes | Read-only `HELIOS.AIHub.Api` advisory endpoints with bounded spoke concurrency |
| `ai.py` | Reject plaintext HTTP, redirectable credentials, and CLI key arguments | `helios-ai engines` and `helios-ai engine-plan` |
| Hermes/XCore training loop + pseudo-runner | Preserve workflow vocabulary only; reject synthetic scores as learning evidence | Candidate-only recommendations; real outcomes remain in `ILearningStore` |
| Reboot marker and local repair logs | Reject stale machine state and host/user metadata | Live diagnostics must generate fresh, redacted evidence |
| Azure dev/VNet/DNS/Key Vault scripts | Preserve resource intent; reject direct execution | Parameterized Bicep/what-if workstream, never raw import |
| M365 security script | Reject immediate tenant-wide policy and paid-plan mutations | Future policy intent with report-only staging, exclusions, licensing, and approval |
| WinRE scheduled-task script | Reject unsigned arbitrary SYSTEM execution | Separate signed Windows-recovery workstream, outside this cloud control plane |

## Runtime contract

The catalog exposes `implemented`, `prototype`, and `concept` maturity. An implemented
entry must name repository evidence, but that does not imply it is loadable in the current
process. `runtime_available` reports the supplied managed/native snapshot;
`PythonInsightsSpoke` populates it from the managed host and `NativeGate`, while direct
Python callers default both to unavailable. CUDA remains an explicit caller declaration.
Recommendations obey a hard separation:

- checked-in implementation, tests, and an available runtime → `selected_engines`;
- recovered prototype/concept vocabulary → `candidate_engines`.

Candidates are never imported, installed, trained, or executed by the catalog, REST API,
CLI, or MCP tools. Turning one into an implemented capability requires a normal code
change and tests that prove its boundary.

The Python subprocess boundary admits at most four concurrent processes. Its REST
endpoints are loopback-only unless `HELIOS_PYTHON_SPOKE_API_KEY` is configured and sent as
`X-HELIOS-Spoke-Key`. Hosted deployments must still put `/v1/*` behind identity-aware
ingress and request limits.

## Rejected execution hazards

- unauthenticated task/training writes, unbounded request bodies, thread exhaustion, and
  unlocked JSON read-modify-write;
- heuristic cost/security/performance numbers presented as live measurements;
- missing Python packages and modules, node/arm identifier mismatches, and synthetic
  quality/latency stored as if it were learning;
- first-subscription selection, broad tenant consent, immediate Conditional Access,
  permanent vault administration, placeholder secret versions, and suppressed failures;
- public or incorrectly reconciled networking, orphan billable resources, unpinned tool
  installation, and machine-wide defaults that can redirect later CLI commands;
- unsigned arbitrary scripts scheduled as SYSTEM.

## Next infrastructure extraction

The network and vault ideas belong in a separate, reviewable Bicep slice: selected
subscription, CIDR collision checks, parameterized subnets, private DNS zone groups,
managed identity/OIDC, metadata-only secret names, consistent ownership tags, and
`what-if` evidence before any apply. No raw `.crdownload` file is a deployment input.
