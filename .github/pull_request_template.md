## Outcome

<!-- One sentence: what is true after this merges that was not before. -->

## What changed

-

## Verification

<!-- Paste real output/evidence for the gates you ran. Local gate commands (CLAUDE.md): -->

```bash
dotnet build HELIOS.sln -c Release
dotnet test tests/HELIOS.AIHub.Tests -c Release
cd src/ai/python && python3 -m pytest tests
bicep build infra/main.bicep --stdout
```

## Review loop

Copilot and Codex auto-review this PR. Address their feedback or reply why not —
`@codex address that feedback` is available for follow-up fixes. Never merge on a
red or skipped required check.
