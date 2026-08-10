# HELIOS Operator for Claude Code

This project-scoped plugin adds:

- `/helios-operator:operate-helios` — the operating workflow;
- `@helios-operator:fabric-operator` — a specialist coordinating repo, MCP, Azure
  preflight, and model handoffs;
- the `operator` MCP server — the existing HELIOS AI tools plus four durable-context
  tools.

Prerequisites: Claude Code and the .NET 8 SDK. Start Claude Code from the root of a HELIOS
checkout.

## Test the branch directly

```bash
claude --plugin-dir ./plugins/helios-operator
```

Run `/mcp`, then `/helios-operator:operate-helios`.

## Install from the repository marketplace

After the plugin is on the repository's default branch:

```text
/plugin marketplace add Yolkster64/helios-platform
/plugin install helios-operator@helios-platform
```

Choose project scope. The committed `.claude/settings.json` also recommends and enables
the plugin after workspace trust. Claude Code still asks for the normal project MCP trust
decision.

The plugin performs no automatic cloud or GitHub mutation. Azure inventory is opt-in and
read-only; deployment and merge remain explicit approval boundaries.
