# HELIOS Integration Contracts

This directory contains the transport-neutral contracts shared by HELIOS agents,
workflows, connectors, fleet workers, and cloud operations. It does not grant execution,
connector, or deployment authority.

## Version 1 files

- `integration-event.v1.schema.json` defines the common event envelope.
- `integration-event-types.v1.json` registers the initial command, result, approval,
  deployment, connector, and fleet event vocabulary.
- `repository-capabilities.v1.schema.json` defines the repository authority format.
- `repository-capabilities.v1.json` records current, planned, historical, satellite, and
  recovery roles without treating a planned rename as already complete.
- `examples/` contains inert, non-networked compatibility fixtures.

The contract was adapted from the historical M0nado event and repository maps and is
reconciled with the merged Yolkster cutover topology. Exact source blob SHAs are recorded
in `repository-capabilities.v1.json`. Cross-repository policy remains governed by
`Heli0s-Dynamics/adaptive-multibrain-bootstrap`; the current Yolkster product repository
distributes and executes this version of the contract.

## Envelope rules

Every persisted event has:

- an immutable `eventId` and retry-stable `idempotencyKey`;
- a `correlationId` and optional `causationId`;
- the exact Git `sourceSha` of the code that emitted it;
- an explicit `dataClassification`;
- an actor, environment, registered event type, and payload;
- at least one durable link with `rel: receipt`.

The receipt is evidence that the event was persisted or delivered. It is not proof that a
deployment was approved, that a remote system accepted a mutation, or that an AI provider
was ready. Approval, deployment, and connector outcomes use separate event types.

Never put keys, tokens, passwords, connection strings, private URLs, or raw credential
output in an event. Classification is routing evidence, not permission: every connector
must still enforce its destination policy before egress.

## Compatibility policy

- Producers must use a registered event type and validate before publishing.
- Consumers must reject unsupported major versions, missing receipts, malformed source
  SHAs, and unknown top-level fields.
- Consumers may interpret `payload` by event type. New optional payload fields are
  backwards-compatible; removing or changing a field requires a new event type or major
  envelope version.
- Event IDs, correlation IDs, idempotency keys, and receipts are immutable after publish.
- Repository authority changes require a reviewed registry update; a planned repository
  never becomes active merely because its name appears here.

Run the dependency-free validation locally:

```bash
python3 scripts/validation/validate_integration_contracts.py
python3 -m unittest discover -s scripts/validation/tests -p 'test_integration_contracts.py' -v
```

## MCP boundary

This is an application event envelope, not an MCP wire-protocol replacement. MCP tools
can return or persist these objects as structured results and receipts. Tool definitions
still need focused names, explicit input/output schemas, accurate safety annotations, and
separate authorization. OpenAI's current guidance supports tool-only MCP servers without
UI resources and recommends reviewing and logging data shared with remote MCP servers:

- <https://developers.openai.com/plugins/build/mcp-server>
- <https://developers.openai.com/api/docs/guides/tools-connectors-mcp>

The future hosted transport can therefore expose the existing C# tools without changing
this envelope. Streamable HTTP hosting, identity-aware ingress, Service Bus, and Azure
deployment remain separate, disabled-by-default work lanes.
