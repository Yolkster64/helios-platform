# Return a Claude Code handoff to ChatGPT

`workspace_agent_handoff.py` lets Claude Code, Codex, or another approved local
process send a summary to a published ChatGPT Workspace Agent. Reusing a
`conversation_key` continues that agent's conversation. It does **not** insert a
message into an arbitrary existing chat, including the chat that set up HELIOS.
Open the returned `conversation_url` to continue there. The endpoint queues work;
the completed answer is available in ChatGPT, not in the API response.
[OpenAI trigger contract](https://developers.openai.com/workspace-agents/trigger-runs).

## Connect once

1. Create or select a HELIOS Workspace Agent, give it the required approved
   connectors, and test its instructions in Preview. Add an API channel, publish
   it, and retain its `agtch_...` channel ID. Share the agent with the token owner.
   [OpenAI setup walkthrough](https://developers.openai.com/cookbook/examples/chatgpt/workspace_agents/workspace-agents-api-trigger).
2. An administrator enables Workspace Agents and personal access tokens in
   **Admin → Permissions & roles**. Create a token with the **Workspace Agents**
   scope under **Admin → Access tokens**, then store it in your secret manager.
   A platform `OPENAI_API_KEY` cannot substitute for this credential.
   [OpenAI authentication](https://developers.openai.com/workspace-agents/authentication).
3. Have the trusted local session or job inject these values:

   | Variable | Value supplied outside the repository |
   | --- | --- |
   | `HELIOS_WORKSPACE_AGENT_TOKEN` | Workspace Agent access token |
   | `HELIOS_WORKSPACE_AGENT_CHANNEL_ID` | Published API channel's `agtch_...` ID |

4. Run the offline check from the repository:

   ```bash
   python3 scripts/bootstrap/workspace_agent_handoff.py
   ```

The result reports presence only. `configured_unverified` means the two variables
exist; it does not verify access. This helper creates no agent or token, opens no
login flow, and reads no token files or other provider credentials.

## Send a handoff

Have Claude write a short summary containing the repository, commit SHA, issue/PR
links, completed checks, and the next requested action. Keep raw credentials out
of that summary. Then send it through stdin:

```bash
python3 scripts/bootstrap/workspace_agent_handoff.py send \
  --conversation-key helios-control \
  --event-id helios-review-001 < .helios/handoffs/claude-summary.txt
```

PowerShell 7:

```powershell
Get-Content -Raw .helios/handoffs/claude-summary.txt |
  python scripts/bootstrap/workspace_agent_handoff.py send --conversation-key helios-control --event-id helios-review-001
```

`--send` also works as the first argument. The explicit action runs without an
extra interactive prompt when its credentials and input are available. The
default `plan` and `status` actions remain offline. Each accepted send prints JSON
containing the conversation link, event ID, and a run ID when supplied by the API;
it never prints the handoff text or credential. Accepted work may still be queued.

The helper requests beta run tracking. Poll once using the returned ID:

```bash
python3 scripts/bootstrap/workspace_agent_handoff.py poll --run-id apirun_RETURNED_ID
```

Polling reports the documented run state without printing the agent's output or
server error details. `completed` and `failed` are terminal; `suspended` requires
attention in the agent conversation. No polling loop runs automatically.
[Run tracking](https://developers.openai.com/workspace-agents/trigger-runs).

## Delivery and limits

Use one event ID for one input event. A fresh send generates an ID if omitted.
Retain the returned ID: after an `unknown` result, inspect the conversation or
repeat the same input with the **same** `--event-id`. An idempotency key is separate
from the conversation key; a new event in the same thread needs a new event ID.
The service supports deduplication through that header.
[Idempotency contract](https://developers.openai.com/workspace-agents/trigger-runs).

This client never retries or follows redirects. It connects only to
`https://api.chatgpt.com`, verifies TLS, and bypasses environment proxy discovery.
Its local limits are 64 KiB of UTF-8 input, 64 KiB of response data, a 20-second
network deadline (`--timeout` accepts 1–60), 128 ASCII characters for conversation
and event keys, and bounded path-safe IDs. These are HELIOS client limits, not
claims about server limits. Network interruption or an unusable success receipt
leaves send delivery `unknown`; a subsequent automatic resend is not assumed safe.

Exit codes: `0` for an offline report, accepted send, or valid non-failed poll;
`2` for missing configuration or invalid local input; `3` for rejected/unknown
delivery, an unverified poll, or a failed agent run.

Verification uses inert HTTPS responses:

```bash
python3 -m unittest scripts.verify.tests.test_workspace_agent_handoff -v
```

No live Workspace Agent trigger or delivery receipt was produced during this
implementation. The token and published channel remain required for activation.
