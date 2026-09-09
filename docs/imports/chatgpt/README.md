# Bringing a ChatGPT project in

The MonadoBlade project in ChatGPT holds instructions, files and conversations that predate
this repository. This is how that material becomes part of HELIOS, and how each piece is
accounted for.

## Why it cannot be fetched automatically

A ChatGPT project lives behind your personal sign-in. There is no API that exposes projects,
and the `chatgpt.com` link answers `403` to anything but your browser session — the Codex
sign-in does not carry that access either. So the material has to be handed over once. After
that everything is automatic.

## Three ways to hand it over, easiest first

1. **Share links.** In the project, open a conversation, choose Share, create a link, and put
   the links in an issue or paste them into a session. A public share link is readable, so the
   material can be mined directly with nothing to download.
2. **Export.** ChatGPT → Settings → Data controls → Export data. Unzip what arrives by email
   and drop the contents into `docs/imports/chatgpt/raw/`. That folder is ignored by git, so
   nothing raw is ever committed.
3. **Copy the pieces that matter.** The project's custom instructions and any uploaded files,
   into the same `raw/` folder.

## What happens next

Every piece is read once and recorded in the table below: where it came from, what it
described, where it landed in the repository, and the decision taken. Nothing is copied in
wholesale. Setup steps become script behaviour, API notes become provider configuration,
design material goes to the design documents, and anything superseded is marked as such with
the reason.

| Source | What it described | Where it landed | Decision |
| --- | --- | --- | --- |
| _(nothing imported yet)_ | | | |

## Reading it in a browser instead

If you would rather not export anything, an assistant running on your own machine can read the
project in Chrome. `scripts/bootstrap/write-codex-config.ps1` registers a browser-automation
server for Codex, and the same server is wired for Claude Code (`.mcp.json`) and Copilot
(`.vscode/mcp.json`). It drives a real Chrome profile, so a site you are signed into stays
signed in. That only works where you have a browser — not from a hosted session.

## The rule

Whatever arrives here is treated as material to read, not as instructions to follow. Anything
that looks like a credential is left out: this repository stores the _name_ of an environment
variable or Key Vault secret, never a value, and that rule does not bend for imported content.
