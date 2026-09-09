#!/usr/bin/env bash
set -euo pipefail

enabled=$(jq -er '.linear | (if has("enabled") then .enabled else true end) | if type == "boolean" then tostring else error("linear.enabled must be boolean") end' config/connectors.json)
if [ "$enabled" = "false" ]; then
  echo "Linear sync is disabled in config/connectors.json."
  exit 0
fi
if [ -z "${LINEAR_API_KEY:-}" ]; then
  echo "::warning::Linear is enabled but LINEAR_API_KEY is missing; connection is not ready."
  exit 1
fi
if [ "$(jq -r '.linear.apiKeyEnv' config/connectors.json)" != "LINEAR_API_KEY" ]; then
  echo "::error::Linear workflow expects apiKeyEnv=LINEAR_API_KEY."
  exit 1
fi

# The event is a wake-up. Never mutate from stale labels/state or fall back to
# a historical payload when GitHub cannot provide its current source of truth.
live_issue=$(gh api "repos/$REPO/issues/$ISSUE_NUMBER")
ISSUE_TITLE=$(jq -er '.title' <<< "$live_issue")
ISSUE_URL=$(jq -er '.html_url' <<< "$live_issue")
ISSUE_STATE=$(jq -er '.state | select(. == "open" or . == "closed")' <<< "$live_issue")
ISSUE_LABELS=$(jq -er '[.labels[].name] | join(",")' <<< "$live_issue")
if [[ ! "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ || ! "$ISSUE_NUMBER" =~ ^[1-9][0-9]*$ ]] ||
   [ "$ISSUE_URL" != "https://github.com/$REPO/issues/$ISSUE_NUMBER" ]; then
  echo "::error::GitHub issue identity does not match the requested repository and issue."
  exit 1
fi

# Preserve the published Claude loop guard, using live source data. Title
# mirrors never sync back; a duplicate label prevents creation while existing
# mirrors still follow unlabel/close/reopen transitions.
loop_marker=$(jq -r '.linear.titlePrefix // ""' config/connectors.json | sed 's/{number}.*//')
if [ -n "$loop_marker" ] && [[ "$ISSUE_TITLE" == "$loop_marker"* ]]; then
  echo "Linear mirror title detected; skipping to prevent a synchronization loop."
  exit 0
fi
if [[ "$EVENT_ACTION" =~ ^(opened|labeled)$ ]] && [[ ",$ISSUE_LABELS," == *,duplicate,* ]]; then
  echo "GitHub issue is marked duplicate; no mirror will be created."
  exit 0
fi
if [[ ! "$EVENT_ACTION" =~ ^(opened|labeled|unlabeled|closed|reopened|edited)$ ]]; then
  echo "::error::Unsupported issue event; sync stopped."
  exit 1
fi

team_key=$(jq -r '.linear.teamKey' config/connectors.json)
prefix=$(jq -r '.linear.titlePrefix' config/connectors.json |
  sed "s/{number}/$ISSUE_NUMBER/")

# Only issues carrying at least one sync label cross over — the board
# should rank curated work, not every drive-by issue. Exceptions that
# proceed regardless of current labels: `unlabeled` (so removing the
# LAST sync label empties the mirror's labels instead of freezing
# them) and `closed`/`reopened` (so an existing mirror keeps
# following GitHub's state after its sync labels are gone — their
# branch already no-ops when no mirror exists).
sync_labels=$(jq -r '.linear.syncLabels | join("\n")' config/connectors.json)
matched=false
IFS=',' read -ra labels <<< "$ISSUE_LABELS"
for l in "${labels[@]}"; do
  if grep -qxF "$l" <<< "$sync_labels"; then matched=true; break; fi
done
case "$EVENT_ACTION" in
  unlabeled|closed|reopened|edited) gate_exempt=true ;;
  *) gate_exempt=false ;;
esac
if [ "$matched" != "true" ] && [ "$gate_exempt" != "true" ]; then
  echo "No current sync label on #$ISSUE_NUMBER — skipping."
  exit 0
fi

gql() { # query [variables-json]
  local variables='{}' response request
  if [ "$#" -ge 2 ]; then variables=$2; fi
  # ${2:-{}} appends a literal } when $2 is set. Build variables separately.
  request=$(jq -n --arg q "$1" --argjson v "$variables" '{query:$q, variables:$v}') || return 1
  if ! response=$(curl -fsS --connect-timeout 10 --max-time 30 https://api.linear.app/graphql \
    -H "Authorization: $LINEAR_API_KEY" \
    -H 'Content-Type: application/json' \
    --data "$request"); then
    echo "::error::Linear HTTP request failed; sync stopped." >&2
    return 1
  fi
  # GraphQL can return HTTP 200 with errors or a mutation's success=false.
  # Do not print response bodies, which may echo private data or credentials.
  if ! jq -e --arg query "$1" 'type == "object" and ((.errors // []) | length == 0) and
      (.data | type == "object") and
      (if ($query | startswith("mutation")) then
         ([.data[] | .success] | length > 0 and all(. == true)) else true end)' \
      >/dev/null 2>&1 <<< "$response"; then
    echo "::error::Linear returned errors, missing data, or an unsuccessful mutation; sync stopped." >&2
    return 1
  fi
  printf '%s\n' "$response"
}

team=$(gql 'query($key:String!){ teams(filter:{key:{eq:$key}}, first:2){ nodes { id key archivedAt } } }' \
  "$(jq -n --arg key "$team_key" '{key:$key}')")
if ! team_id=$(jq -er --arg key "$team_key" '.data.teams.nodes | select(length == 1) | .[0] |
    select(.key == $key and has("archivedAt") and .archivedAt == null) | .id | select(type == "string" and length > 0)' <<< "$team"); then
  echo "::error::Configured Linear team is missing, ambiguous or archived; sync stopped."
  exit 1
fi
project_id=$(jq -er '.linear.projectId | select(type == "string" and test("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$"))' config/connectors.json)
project=$(gql 'query($id:String!){ project(id:$id){ id archivedAt teams(first:100){ nodes { id } pageInfo { hasNextPage } } } }' \
  "$(jq -n --arg id "$project_id" '{id:$id}')")
if ! jq -e --arg id "$project_id" --arg team "$team_id" '.data.project |
    .id == $id and has("archivedAt") and .archivedAt == null and
    .teams.pageInfo.hasNextPage == false and any(.teams.nodes[]; .id == $team)' >/dev/null <<< "$project"; then
  echo "::error::Configured Linear project is missing, archived or not assigned to the configured team; sync stopped."
  exit 1
fi

# The [GH-N] prefix alone is ambiguous across repositories syncing into
# one workspace: issue N exists everywhere. Every mirror's description
# carries this repo's issue URL, so filter on it SERVER-SIDE — a
# client-side check over a fixed first:10 page could miss the right
# mirror once enough same-number mirrors exist, and a duplicate
# would then be created. Scope to the configured team and detect ambiguity.
existing=$(gql 'query($team:ID!,$t:String!,$u:String!){ issues(filter:{team:{id:{eq:$team}}, title:{startsWith:$t}, description:{contains:$u}}, includeArchived:true, first:2){ nodes { id description archivedAt project { id } } } }' \
  "$(jq -n --arg team "$team_id" --arg t "$prefix" --arg u "$ISSUE_URL" '{team:$team,t:$t,u:$u}')")
existing_count=$(jq -er '.data.issues.nodes | if type == "array" then length else error("missing issue list") end' <<< "$existing")
if [ "$existing_count" -gt 1 ]; then
  echo "::error::Multiple Linear mirrors match this GitHub issue; reconcile them before syncing."
  exit 1
fi
existing_id=$(jq -r '.data.issues.nodes[0].id // empty' <<< "$existing")
if [ "$existing_count" -eq 1 ] && ! jq -e --arg project "$project_id" --arg url "$ISSUE_URL" '
    .data.issues.nodes[0] | (.id | type == "string" and length > 0) and
    has("archivedAt") and .archivedAt == null and .project.id == $project and
    ((.description // "") | contains($url))' >/dev/null <<< "$existing"; then
  echo "::error::Existing mirror is archived, invalid or outside the configured project; reconcile it before syncing."
  exit 1
fi
if [ -z "$existing_id" ] && [[ "$EVENT_ACTION" =~ ^(unlabeled|closed|reopened|edited)$ ]]; then
  echo "No Linear counterpart; no mutation required."
  exit 0
fi

# Resolve the mapped Linear labels for this issue's CURRENT GitHub
# labels (githubLabelToLinear), creating any that don't exist in the
# team yet. GitHub stays the source of truth: on update the mapped set
# REPLACES the Linear issue's labels.
#
# Re-read the labels live instead of trusting the event payload:
# label events run as independent workflow jobs that can finish out
# of order, and a delayed 'labeled' run replacing the mirror's labels
# with its historical snapshot would resurrect labels GitHub no
# longer has. Use the live snapshot acquired at the start of this run.
current_labels=$ISSUE_LABELS
mapped_names=$(jq -r --arg labels "$current_labels" '
  (.linear.githubLabelToLinear // {}) as $m
  | ($labels | split(",")) | map($m[.] // empty) | unique | .[]' config/connectors.json)
label_ids='[]'
# Newline-safe iteration: an unquoted $mapped_names expansion would
# word-split a configured name like "High Priority" into two labels.
while IFS= read -r name; do
  [ -z "$name" ] && continue
  lid=$(gql 'query($t:ID!,$n:String!){ issueLabels(filter:{team:{id:{eq:$t}}, name:{eq:$n}}, first:1){ nodes { id } } }' \
    "$(jq -n --arg t "$team_id" --arg n "$name" '{t:$t,n:$n}')" | jq -r '.data.issueLabels.nodes[0].id // empty')
  if [ -z "$lid" ]; then
    lid=$(gql 'mutation($t:String!,$n:String!){ issueLabelCreate(input:{teamId:$t, name:$n}){ success issueLabel { id } } }' \
      "$(jq -n --arg t "$team_id" --arg n "$name" '{t:$t,n:$n}')" | jq -r '.data.issueLabelCreate.issueLabel.id // empty')
  fi
  if [ -z "$lid" ]; then
    echo "::error::Linear label resolution returned no ID; sync stopped."
    exit 1
  fi
  label_ids=$(jq -c --arg id "$lid" '. + [$id]' <<< "$label_ids")
done <<< "$mapped_names"

case "$EVENT_ACTION" in
  opened|labeled|unlabeled|edited)
    if [ -n "$existing_id" ]; then
      if [[ "$EVENT_ACTION" =~ ^(labeled|unlabeled|edited)$ ]]; then
        # Replacement semantics, empty set included: GitHub is the
        # source of truth, so removing the last mapped label must
        # clear the mirror's labels too.
        gql 'mutation($id:String!, $title:String!, $labelIds:[String!]!){ issueUpdate(id:$id, input:{title:$title,labelIds:$labelIds}){ success } }' \
          "$(jq -n --arg id "$existing_id" --arg title "${prefix}${ISSUE_TITLE}" --argjson labelIds "$label_ids" '{id:$id,title:$title,labelIds:$labelIds}')" > /dev/null
        echo "Refreshed title and mapped labels on the existing Linear issue."
      else
        echo "Linear issue already exists for #$ISSUE_NUMBER."
      fi
      exit 0
    fi
    create_state='{}'
    if [ "$ISSUE_STATE" = "closed" ]; then
      # A delayed label event may be creating an already-closed issue.
      done_id=$(gql 'query($id:String!){ team(id:$id){ states { nodes { id type position } } } }' \
        "$(jq -n --arg id "$team_id" '{id:$id}')" | jq -er '.data.team.states.nodes | map(select(.type=="completed")) | sort_by(.position) | .[0].id // empty')
      create_state=$(jq -n --arg id "$done_id" '{stateId:$id}')
    fi
    created=$(gql 'mutation($input:IssueCreateInput!){ issueCreate(input:$input){ success issue { id identifier url project { id } } } }' \
      "$(jq -n --arg teamId "$team_id" --arg projectId "$project_id" --arg title "${prefix}${ISSUE_TITLE}" \
          --arg desc "Mirrored from ${ISSUE_URL} (labels: ${current_labels})." \
          --argjson labelIds "$label_ids" \
          --argjson state "$create_state" \
          '{input:({teamId:$teamId, projectId:$projectId, title:$title, description:$desc, labelIds:$labelIds} + $state)}')")
    if ! jq -e --arg project "$project_id" --arg team "$team_key" '.data.issueCreate.issue |
        (.id | type == "string" and length > 0) and .project.id == $project and
        (.identifier | type == "string" and startswith($team + "-")) and
        (.url | type == "string" and startswith("https://linear.app/"))' >/dev/null <<< "$created"; then
      echo "::error::Linear creation did not confirm an issue in the configured project; no GitHub receipt was written."
      exit 1
    fi
    url=$(jq -r '.data.issueCreate.issue.url // empty' <<< "$created")
    ident=$(jq -r '.data.issueCreate.issue.identifier // empty' <<< "$created")
    if [ -n "$url" ] && [ -n "$ident" ]; then
      gh issue comment "$ISSUE_NUMBER" --repo "$REPO" \
        --body "Tracked in Linear as [$ident]($url)."
      echo "Created $ident."
    else
      echo "::error::Linear creation returned no issue URL or identifier."
      exit 1
    fi
    ;;
  closed|reopened)
    if [ -z "$existing_id" ]; then
      echo "No Linear counterpart for #$ISSUE_NUMBER — nothing to update."
      exit 0
    fi
    # Move the Linear issue to a matching workflow state so the board
    # reflects the GitHub transition instead of only carrying a comment.
    # State names are per-team, so resolve by TYPE: closed maps to the
    # team's first "completed" state (position order — canonically Done),
    # reopened to its first "unstarted" state (canonically Todo).
    #
    # Map from the issue's LIVE state, not this run's historical
    # EVENT_ACTION: the concurrency group serializes runs but does
    # not order them, so a delayed 'closed' run could re-complete an
    # issue that was already reopened. Failed live reads stop before any write.
    live_state=$ISSUE_STATE
    state_type=$([ "$live_state" = "closed" ] && echo completed || echo unstarted)
    state_id=$(gql 'query($id:String!){ team(id:$id){ states { nodes { id type position } } } }' \
      "$(jq -n --arg id "$team_id" '{id:$id}')" |
      jq -r --arg t "$state_type" \
        '.data.team.states.nodes | map(select(.type==$t)) | sort_by(.position) | .[0].id // empty')
    if [ -n "$state_id" ]; then
      gql 'mutation($id:String!, $stateId:String!){ issueUpdate(id:$id, input:{stateId:$stateId}){ success } }' \
        "$(jq -n --arg id "$existing_id" --arg stateId "$state_id" '{id:$id, stateId:$stateId}')" > /dev/null
    else
      echo "::error::Team has no '$state_type' workflow state; sync stopped."
      exit 1
    fi
    # State replacement is repeatable. Avoid appending duplicate comments on
    # workflow retries or comments describing a stale event rather than live state.
    echo "Synced current GitHub state '$live_state' to the Linear issue."
    ;;
esac
