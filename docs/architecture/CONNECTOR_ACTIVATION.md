# Slack and Linear activation

GitHub is the engineering source of truth. These workflows connect its issue
and build events to Linear and Slack. A connected ChatGPT app does not supply
credentials to GitHub Actions or establish a workstation CLI session.

## Current implementation

| Surface | Implemented behavior | Evidence still needed |
|---|---|---|
| Linear | Curated issue mirror to team `JOH`; live GitHub title/labels/state; team-scoped mirror lookup including archived records; ambiguity stops; GraphQL errors and unsuccessful mutations fail | Authorized Actions credential; one existing issue updates once without a duplicate |
| Slack | CI failure and recovery notifications, bounded history lookup, fork-safe comparison, escaped text, acknowledged webhook response | Approved installation channel and Actions webhook; one authorized delivery receipt |
| Production workers | These Actions workflows are separate from the governed runtime outbox | JOH-52: persistent idempotency, retries, incident threading, deployment and delivery evidence |

`config/connectors.json` contains policy and credential variable names only.
`enabled: false` skips without network access. `enabled: true` without the
required secret fails its connector workflow, leaving the originating build's
result unchanged. A green connector test uses inert adapters, not live delivery.

The Slack incoming webhook is bound to the channel selected at installation.
The `channels` mapping and `botTokenEnv` are future service metadata; setting them
does not route webhook messages. Confirm the desired destination before creating
or replacing a webhook. `#helios-control-plane` is the existing operator channel;
its use by this notifier has not been verified.

For `failures-and-recovery`, success after a failed, timed-out, action-required,
or startup-failed predecessor is a recovery. Routine successes and cancellations
are quiet. Compare the previous attempt for reruns, otherwise the preceding run
on the same workflow, branch, event and source repository. Unavailable or
exhausted history fails visibly. Slack transport retries are deliberately manual:
an ambiguous network failure may have delivered, so check the channel before
retrying. Exactly-once delivery is not claimed.

Linear mutations are not automatically retried. A later workflow looks up the
existing mirror first. Concurrent issue events are serialized per GitHub issue;
ambiguous matches stop. This does not replace persistent worker idempotency, and
concurrent creation of a shared label by different issues may require a retry.
Disable Linear's native issue mirroring back into this repository before
activation to prevent the previously observed duplication loop. Keep PR links
if desired. See the owner instructions in [Connections setup](CONNECTIONS_SETUP.md).

## Activation sequence in the intended operator session

1. Review and land the connector PR through the repository's normal gates.
   Event listeners use the default branch; opening a draft does not activate them.
2. Verify `gh auth status --hostname github.com --active`, then confirm the
   intended repository with `gh repo view Yolkster64/helios-platform`.
3. Confirm team John (`JOH`), one-way issue sync, and the intended Slack channel.
4. An authorized secret administrator provisions `LINEAR_API_KEY` and
   `SLACK_WEBHOOK_URL` through GitHub's secret UI or `gh secret set NAME --repo
   Yolkster64/helios-platform` using its secure prompt. Never put secret values
   in command arguments, commits, issue bodies, logs, or assistant messages.
5. Review the exact target/payload before a live delivery test. Use one existing
   mirrored GitHub issue and one approved Slack message. Capture the workflow
   URL, source SHA, destination and resulting issue/message link. Verify no
   duplicate issue was created and a recovery is correctly detected.

Offline verification (no credentials or service requests):

```bash
python3 scripts/verify/tests/test_connectors.py
```

## Related work and boundaries

- [JOH-52](https://linear.app/641974/issue/JOH-52/deploy-idempotent-slack-and-linear-workers)
  owns production worker activation.
- [JOH-20](https://linear.app/641974/issue/JOH-20/fleet-github-linear-and-slack-synchronization-agents)
  tracks cross-surface agent behavior.
- [JOH-8](https://linear.app/641974/issue/JOH-8/edm-v5-implement-github-linear-and-slack-workflow-synchronization)
  tracks governed synchronization. These items are not completed by an Actions repair.

The platform's fallback chains and the governed AIHub's explicit, no-fallback
contract still require convergence. This notifier and issue mirror send metadata,
not inference requests. Do not route governed tasks through a legacy fallback
chain until provider/model, credential mode, classification and egress rules have
been agreed and tested. Keep provider activation distinct from connector setup.

## Established SharePoint evidence destination

On 2026-09-05, the existing [JOH-36 control-plane record](https://linear.app/641974/issue/JOH-36/deploy-helios-cloud-only-control-plane-and-online-visualization)
identified [HELIOS_CONTROL_PLANE_CURRENT.md](https://heli0s-my.sharepoint.com/personal/jmore_heli0s_onmicrosoft_com/Documents/Helios/Governance/Architecture/Integration-Fabric/HELIOS_CONTROL_PLANE_CURRENT.md)
as its status index. Direct folder enumeration and file metadata lookup succeeded:

- Host: `heli0s-my.sharepoint.com`
- Site path: `/personal/jmore_heli0s_onmicrosoft_com`
- Document library: `Documents`
- Drive-relative folder: `Helios/Governance/Architecture/Integration-Fabric`
- Existing status index: `HELIOS_CONTROL_PLANE_CURRENT.md`

This is a recovered, previously linked project destination, not an inferred
replacement for a team site. The separate `heli0s.sharepoint.com/sites/helios`
lookup still returns 404. Keyword search missed these Markdown/JSON artifacts;
use the existing link and folder listing to rediscover them. Folder and metadata
access do not prove file-content retrieval, write permission, a runtime Graph
identity, or a deployed SharePoint worker. The raw download attempt returned 403;
preserve the current file until its contents can be read before any update.

Enterprise control setup still needs authorized repository-admin access; a 404
alone cannot distinguish an absent repository from an inaccessible one. The
GitHub app's repository access does not establish administration rights.

Implementation references: [Linear error handling](https://linear.app/developers/graphql),
[Slack incoming webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/),
[GitHub workflow runs](https://docs.github.com/en/rest/actions/workflow-runs).
