# ARM template mirror (GENERATED — do not hand-edit)

`main.json` is **generated** from `infra/main.bicep`. Never edit it by hand: change the
Bicep source (and its `modules/`) instead, then regenerate. CI
(`.github/workflows/infra-validate.yml`) recompiles the Bicep on every PR touching
`infra/**` and fails if this file has drifted from what the Bicep compiles to.

## Regenerate

From the repo root:

```bash
bicep build infra/main.bicep --outfile infra/arm/main.json
# or, without a standalone bicep binary:
az bicep build --file infra/main.bicep --outfile infra/arm/main.json
```

## Deploy

```bash
az group create -n helios-core-rg -l centralus
az deployment group create -g helios-core-rg \
  --template-file infra/arm/main.json \
  --parameters anthropicApiKey="$ANTHROPIC_API_KEY" openaiApiKey="$OPENAI_API_KEY"
```

The parameter surface is identical to `infra/main.bicep` / `infra/main.bicepparam`.
If you want a plain-JSON parameters file for an ARM-only pipeline, compile one at deploy
time (don't commit it — secrets stay out of the repo):

```bash
az bicep build-params --file infra/main.bicepparam --outfile /tmp/main.parameters.json
```

## Why this exists

Some deployment surfaces consume only compiled ARM JSON:

- **ARM-only pipelines** — CD systems without a Bicep toolchain can take
  `infra/arm/main.json` as-is.
- **Azure portal template deployment** — "Deploy a custom template" accepts pasted or
  uploaded ARM JSON, not Bicep.

Bicep remains the source of truth and the deployment of record; see `../README.md`
("Three dialects") for how the Bicep, ARM JSON, and Terraform variants relate.
