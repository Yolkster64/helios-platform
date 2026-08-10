# HELIOS Enterprise Promotion Topology

## Purpose

Move reviewed HELIOS work into the user-owned control plane without losing its
origin, validation evidence, or approval history.

## Repository roles

1. `Yolkster64/monado-blade`
   - Hardware, apps, and driver integration laboratory.
   - Produces immutable candidate commits and validation evidence.

2. `M0nado/Helios-Control-Center`
   - Legacy control-center source and immutable migration provenance.
   - Remains read-only during the Yolkster migration.

3. `Yolkster64/helios-platform`
   - User-owned HELIOS system of record.
   - Hosts the operator surface, integration contracts, validation workflows,
     Azure plans, and reviewed promotion records.

4. Optional organization mirrors
   - Receive only reviewed release candidates from the user-owned system of
     record.
   - Never replace `Yolkster64/helios-platform` as the write target.

## Promotion rules

- Every imported change is carried by a task branch and pull request.
- Source repositories are read-only inputs; imports never rewrite their history.
- Candidate references must be immutable 40-character commit SHAs.
- Validation and evidence generation do not authorize Azure deployment.
- Azure changes require a separate what-if, protected environment, and approval.
- OpenAI credentials remain in an environment variable or Azure Key Vault, never
  in Git history, workflow output, Slack, or Linear.
- Slack and Linear receive links, digests, and status receipts only.

## Migration ledger

| Source item | Yolkster disposition |
| --- | --- |
| `M0nado/Helios-Control-Center#1` | Scaffold superseded by the populated platform; no empty `.gitkeep` import. |
| `9ab49b7` | Promotion topology adapted for the user-owned control plane. |
| `14dce41` | Promotion workflow ported with immutable-SHA validation and no deploy permission. |
| `376ded5` | Secretless OpenAI integration example ported. |
| `M0nado/Helios-Control-Center#2` / `51e1147` | Immutable apps-and-drivers promotion evidence preserved. |

## Sequence

`candidate repository` -> `Yolkster64/helios-platform draft PR` -> `validation` ->
`review` -> `merge decision` -> `separately authorized deployment`

Each hop leaves a durable link to the source commit and the evidence used to
evaluate it.
