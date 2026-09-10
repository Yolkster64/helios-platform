# Connect everything

## Do this

Open [Azure Cloud Shell](https://shell.azure.com), pick **Bash**, paste this:

```bash
git clone https://github.com/Yolkster64/helios-platform && cd helios-platform && bash scripts/bootstrap/connect.sh
```

Already cloned? `cd helios-platform && bash scripts/bootstrap/connect.sh`.

That is the whole thing. It connects GitHub, the GitHub CLI, Azure, Key Vault, OpenAI/Codex,
Claude, Azure AI Foundry, Linear, Slack, the editor and agent surfaces and the local fleet, then
prints a short list of anything still waiting on you.

Cloud Shell is the right place: your Azure sign-in is already there, so the entire Azure half
needs nothing from you.

## It asks you for five things, at most

| # | What you do | Why |
| --- | --- | --- |
| 1 | Type a **GitHub code** it prints | Signs in the GitHub CLI; turns on the free GitHub Models lane |
| 2 | Click **Create**, then **Install**, on a GitHub App page | The important one. After this the workflows mint their own credentials every run — no stored token, and no GitHub code ever again |
| 3 | Paste any **API keys** you want, at a hidden prompt | OpenAI, Anthropic, GitHub Models. Straight into Key Vault. Skip any; that provider just stays unconfigured |
| 4 | Type a **Codex code** it prints | The ChatGPT lane |
| 5 | Check the repo is listed at [chatgpt.com/codex settings](https://chatgpt.com/codex/cloud/settings/general) | What makes Codex review every pull request. Already true; the script only verifies |

**Azure OpenAI, Claude on Foundry and Foundry itself need no key.** They use your Azure
sign-in. Nothing you type is ever written to a file or shown on screen.

## The fourteen lanes, and who acts

One run walks every surface this project has. Lanes 1–7 can act for you; lanes 8–12 only
report, because what is left there is a click or a decision that is yours.

| # | Lane | What it does | Who acts |
| --- | --- | --- | --- |
| 0 | persistence | Cloud Shell: the checkout, the CLIs and `.helios` survive a reset | script |
| 1 | github | `gh` device sign-in, code printed in front of you | you type a code |
| 2 | app | The GitHub App: register + install, then every workflow mints its own token per run | you click twice |
| 3 | oidc | The three Azure OIDC variables, so workflows reach Azure with no stored password | script |
| 4 | secrets | Provider keys into Key Vault at a hidden prompt | you paste, or skip |
| 5 | hub | Pulls whatever the vault already holds so the providers resolve | script |
| 6 | codex | The four ChatGPT/OpenAI surfaces at once (see below) | you type a code |
| 7 | foundry | Claude and Azure OpenAI over Entra, no key; resolves `ANTHROPIC_FOUNDRY_RESOURCE` and the `CLAUDE_AZURE_*` identifiers | script |
| 8 | connectors | Linear and Slack: says which of the two repository secrets are set, by name | you set a secret |
| 9 | workspace | The editor and assistant surfaces: the `helios` tool server and the Playwright browser server registered for Claude Code, VS Code/Copilot and Codex, plus the devcontainer and the themed workspace | script |
| 10 | agents | The three GitHub agents — Codex cloud reviews, Copilot dispatch by label, Claude on Foundry | you confirm once |
| 11 | fleet | Hermes and XCore locally, from `config/fleet/fleet-topology.json`; the paid burst pool is printed, never deployed | you say when |
| 12 | m365 | Microsoft 365: the Graph connector and declarative agent are built; enabling them writes to your tenant | you decide |
| 13 | surfaces | Of everything this repository *declares* about itself — rulesets, environments, labels, milestones, repo settings — which are actually applied. Reports, never writes | — |
| 14 | verify | One read-only pass, read as a report rather than an exit code | — |

Run it again whenever. It skips what is done, and the list gets shorter.

## Reading the result

| State | Meaning |
| --- | --- |
| `ok` | Connected and verified |
| `needs-owner` | One action from you; the exact command is printed under it |
| `skipped` | Does not apply here |
| `failed` | Not yours to fix — worth reporting |

Exit `0` nothing left · `2` items listed · `1` a lane failed. The same table is saved to
`.helios/connect-state.json`, which git ignores.

```bash
bash scripts/bootstrap/connect.sh --status        # show the table, change nothing
bash scripts/bootstrap/connect.sh --github-code   # only the GitHub sign-in
bash scripts/bootstrap/connect.sh --skip-secrets  # skip any lane by name
```

Windows: `pwsh scripts/bootstrap/connect.ps1`, same lanes, same options
(`-Status`, `-GitHubCode`, `-Skip secrets`).

## How this fits the control plane

HELIOS Control is one system with one control plane, and connecting is how you take hold of
it. Every lane above feeds the same three surfaces:

- **The hub** (`helios-ai`) routes a task to the right model, or to several at once, and
  records what each one cost. Providers you skipped simply report "unconfigured".
- **The tool set** (24 governed `helios_*` tools over the Model Context Protocol) gives any
  assistant — Claude Code, Codex, Copilot — the same read-only view of status, routing,
  infrastructure and configuration. A second registered server drives a real Chrome through
  Playwright, which is how an assistant reads a page you are signed into.
- **The governed pipeline** applies rulesets, labels, milestones and deployments from the
  manifests in `config/`, on the App credential from step 2, with GitHub's protected
  environments as the only deployment authority.

### ChatGPT and OpenAI are four surfaces, reported as one

They are easy to confuse, and signing in to one does not sign you in to another. The connect
script checks all four and asks only for what is actually missing:

| Surface | What it is | How it connects |
| --- | --- | --- |
| **Cloud** | Codex reviews every pull request | Connected once at chatgpt.com; `codex cloud list` shows the tasks |
| **CLI** | `codex` on the command line, and the hub's `codex` lane | The device code in step 4 |
| **Tools** | HELIOS's 24 governed tools registered *into* Codex, so ChatGPT drives the hub | Automatic, from `write-codex-config.ps1` |
| **API** | The `openai` and `openai-codex` providers | Needs `OPENAI_API_KEY` — the ChatGPT sign-in does **not** produce one |

That last row is the one that surprises people. A ChatGPT sign-in leaves the API key field
empty; the API providers stay unconfigured until you paste a platform key in step 3, and
everything else keeps working meanwhile.

Two lanes are deliberately gated on a decision, not a credential. **Fabric activation**
(`config/fabric/helios-fabric.v1.json`) is an executable contract: it holds targets, gates and
receipt pointers, keeps `productionEnabled` false until you say otherwise, and stays blocked
behind the repository rename to `helios-control`. **Microsoft 365** needs tenant administrator
consent. Neither is something a script should decide.

Where the whole project stands: [PROGRAM.md](PROGRAM.md).

## The optional extras

- **Copilot and Claude on your own machine**: `copilot login`, `claude setup-token`. Browser
  sign-ins, so they only work where you have a browser.
- **Linear's own GitHub sync must be OFF for team JOH**, or the duplicate issues it creates
  keep coming back (lane 8 prints this next to the secret names).
- **The burst fleet**: costs money, so it waits for your word. The command is printed on ask.
- **A ChatGPT project**: export it (Settings → Data controls → Export) or copy its
  instructions and files into `docs/imports/chatgpt/raw/`. Git ignores that folder, so nothing
  raw is committed; each piece is recorded in `docs/imports/chatgpt/README.md`.

## If something looks wrong

```bash
pwsh scripts/bootstrap/auth-doctor.ps1     # every credential lane and what each one wants
pwsh scripts/verify/rest-connect.ps1       # the same, checked against the live services
```

Neither changes anything. Both name the environment variable or Key Vault secret a lane is
missing, never its value.

If a lane reports "PowerShell 7 is not on this host" and you know it is, set `HELIOS_PWSH`
to the interpreter you want the `.ps1` lanes run with. Both twins honour it ahead of their
own guesses: `.tools/pwsh/pwsh` in this checkout, then `pwsh` as the shell finds it
(`connect.ps1` prefers the interpreter already running it, which a `PATH` lookup can miss).

```bash
HELIOS_PWSH=/opt/microsoft/powershell/7/pwsh bash scripts/bootstrap/connect.sh --status
```

The contracts on this page are tested on every change to either twin
(`scripts/verify/tests/test_connect.ps1`, run by `.github/workflows/auth-contracts.yml`). The
run reaches no network: `gh`, `az`, `codex` and every `.ps1` child are replaced by shims, and
the bash orchestrators that do run for real reach the outside world only through those. What
is proved:
that a read-only run writes nothing and never reaches `auto-login.ps1`, that `--json` emits
the report the run built, that a lane needing you always names a command, and that the two
twins report the same lanes in the same order.
