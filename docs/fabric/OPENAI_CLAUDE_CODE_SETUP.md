# OpenAI, Codex, and Claude Code in the HELIOS Fabric

This document binds OpenAI/Codex and Anthropic/Claude Code to the same HELIOS AIHub, MCP, approval, identity, and evidence contracts. It does not contain credentials.

## Common architecture

```text
WinUI 3 Control Center / CLI / IDE client
                  |
          HELIOS typed task contract
                  |
        AIHub routing and policy engine
        /          |           \
   OpenAI       Claude       Foundry/Copilot
        \          |           /
         governed MCP/tool registry
                  |
    GitHub / Azure / DevOps / collaboration
       read -> plan -> request -> approve -> act
```

Provider-specific SDK objects stop at adapters. The WinUI shell consumes provider-neutral task, health, trace, budget, and result contracts.

## OpenAI and Codex

Use project-scoped restricted credentials or another approved platform identity. Runtime configuration refers only to:

```text
OPENAI_API_KEY
OPENAI_PROJECT_ID
OPENAI_ORG_ID
OPENAI_BASE_URL
```

The OpenAI adapter may perform bounded Responses/Agents operations, structured outputs, tracing, and tool calls declared in the HELIOS MCP registry. It may not expose the credential, invoke generic shell/HTTP tools, administer repositories, deploy Azure, or grant permissions.

Recommended setup sequence:

1. Select or create the approved OpenAI project through the secure platform UI.
2. Create a restricted key for the exact HELIOS environment.
3. Store the value locally in an ignored environment file for development or in Azure Key Vault for cloud runtime.
4. Bind only the secret reference to the runtime identity.
5. Run a minimal health request with a cost/output limit and redacted trace.
6. Test timeout, budget, rate-limit, tool-denial, fallback, and error sanitization.
7. Record project/reference metadata and result receipt without the key value.

## Claude Code

Claude Code uses repository instructions and bounded project tooling:

```text
CLAUDE.md
AGENTS.md
config/claude/helios-claude-policy.v1.json
.mcp.json
.claude/agents/*
.claude/commands/*
```

Permitted work includes reading, comparing, editing a reviewed feature branch, building, testing, validating Bicep/PowerShell/JSON/YAML, preparing PRs/issues, and reviewing development what-if evidence through approved tools.

Denied work includes merge, repository rename/transfer/archive, ruleset/environment changes, Azure apply, Entra/RBAC/Graph mutation, Key Vault secret writes/readback, direct Slack/Linear/SharePoint writes, physical Windows administration, and generic unrestricted shell execution.

Credential-bearing CI must load configuration from the trusted default branch. It must not execute pull-request-controlled MCP servers, hooks, plugins, or configuration. Pull-request content is untrusted input to review, not executable policy.

## Agent handoffs

A front-door orchestrator may hand off to:

- architecture curator;
- canonical migration operator;
- WinUI 3 engineer;
- connector contract reviewer;
- Azure plan reviewer;
- security/provenance reviewer;
- Hermes/XCore evaluation worker.

Each handoff carries task ID, classification, budget, deadline, allowed tools, correlation ID, and approval state. Subagents cannot expand their own permissions.

## Tool classes

```text
read       automatic when scoped and redacted
plan       automatic when non-mutating and bounded
request    creates an approval request; performs no external effect
act        requires approved receipt and idempotency key
admin      always outside model authority; owner/admin operation
physical   always local with exact-device state and confirmation
```

OpenAI, Claude, Copilot, Foundry, Hermes, and XCore all use the same classes. A model response can recommend or request an action; it cannot transform a plan into approval.

## Tracing and evidence

Record:

- provider/model and sanitized endpoint class;
- task/correlation/trace IDs;
- input/output token or equivalent usage;
- latency, cost, quality, fallback, and tool decisions;
- source repository and commit;
- redaction profile;
- approval and result receipts;
- sanitized error.

Never record API keys, access/refresh tokens, signed URLs, raw private memory, tenant secrets, or unredacted sensitive prompts in shared evidence.

## Activation gates

Provider activation is blocked until AIHub HC-009 hardening passes. Cloud provider access additionally requires environment-scoped identity, Key Vault references, budget/rate policy, health tests, and rollback/disable instructions. Production remains independently disabled.
