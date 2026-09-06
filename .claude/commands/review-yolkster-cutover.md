Review the current branch against the Yolkster HELIOS cutover contract.

1. Run `python3 scripts/validation/validate_yolkster_cutover.py`.
2. Confirm the branch descends from the latest fetched `main`.
3. Confirm no new WPF/UWP dependency exists under `src/gui`.
4. Confirm all HC-001 through HC-028 records exist exactly once.
5. Compare active repository references with the current alias and target rename.
6. Inspect for secrets, deployment commands, force pushes, repository deletion, or source archival without target proof.
7. Return a PASS/BLOCKED report with exact file paths and commands. Do not merge.
