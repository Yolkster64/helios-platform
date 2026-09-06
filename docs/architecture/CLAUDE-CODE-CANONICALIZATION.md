# Claude Code Canonicalization Contract

Claude Code is already integrated with the HELIOS MCP server and Foundry review lanes. This migration keeps that working implementation and adds a narrower repository-cutover role.

Claude may:

- inspect repositories, diffs, issues, pull requests, checks, and evidence;
- edit allowlisted source and documentation on a review branch;
- build and test;
- validate Bicep;
- prepare an Azure development `what-if` request;
- produce draft issues, draft pull requests, and redacted handoff records.

Claude may not:

- rename, transfer, archive, delete, merge, or force-push repositories;
- alter protected environments, rulesets, reviewers, or bypass settings;
- deploy Azure resources or change Entra/RBAC;
- read back or export secrets;
- write to Slack, Linear, SharePoint, or tenant systems without an explicit connector action;
- perform disk, driver, Defender, BitLocker, TPM, firmware, or boot mutation.

The project MCP server remains the local `dotnet` command in `.mcp.json`. Additional remote connectors are activated separately so an untrusted branch cannot replace MCP configuration while a provider credential is present.
