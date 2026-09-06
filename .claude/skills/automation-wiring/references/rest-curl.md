# REST / curl Reference

HTTP calls that run unattended: flags that make failures visible, auth that does not leak, and
the point at which curl should become an SDK.

## Contents

- [curl flags](#curl-flags-for-automation) · [Auth flows](#auth-flows) · [Not leaking tokens](#not-leaking-tokens) · [Retries](#retries-and-backoff)
- [GitHub REST](#github-rest-specifics) · [Azure REST](#azure-rest-specifics) · [Smoke tests](#from-ad-hoc-curl-to-a-committed-smoke-test) · [When to stop](#when-to-stop-using-curl)

## curl flags for automation

Default curl is built for humans: progress bar on stderr, and it **exits 0 on an HTTP 500**.

| Flag | Why |
|---|---|
| `-sS` | silent **but still print errors** — `-s` alone hides them; always pair |
| `--fail-with-body` | exit 22 on HTTP ≥ 400 *and* print the body (curl ≥ 7.76). Plain `-f`/`--fail` also exits 22 but discards the body, losing the error message |
| `--connect-timeout` / `--max-time` | a hung connect otherwise blocks a CI job indefinitely |
| `--retry N`, `--retry-delay`, `--retry-all-errors` | `--retry-all-errors` (≥ 7.71) also retries connection refused; none of them classify status codes, so hand-roll past the simple case |
| `-L` | follow redirects — curl **drops `Authorization` on cross-host redirect**, by design |
| `-w '%{http_code}'` | status code; pair with `-o /dev/null` for status only |
| `-D -` | dump headers — needed for `Link`, `Retry-After`, rate limits |
| `--data-binary @f` | byte-for-byte; use for any JSON, certificate, or signed payload |
| `-d` / `--data @f` | **strips newlines** — corrupts JSON with embedded newlines and breaks signatures. It exists for HTML form posts |

Capture status and body in one request with `-w '\n%{http_code}'`, then split:
`code=${resp##*$'\n'}; body=${resp%$'\n'*}` — an idiom that recurs below. Extract fields with
`jq -er` (`-e` exits 1 on null/false, `-r` emits a raw string), which turns a missing field into
a script failure instead of letting the literal string `null` flow into the next step.

## Auth flows

**GitHub PAT** — tied to a user, one blast radius, the worst option. Inside Actions
`${{ secrets.GITHUB_TOKEN }}` is scoped, per-job and auto-expiring; it just cannot trigger workflows.

**GitHub App installation token** — preferred. Sign a JWT with the app key, then exchange it:

```bash
now=$(date +%s)
b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$APP_ID" | b64)
sig=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$PEM" -binary | b64)
token=$(curl -sS --fail-with-body -X POST -H "Authorization: Bearer $header.$payload.$sig" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" | jq -er .token)
echo "::add-mask::$token"
```

`iat` is backdated 60s because GitHub rejects a JWT whose `iat` is even a second in the future —
a common clock-skew failure; `exp` over 10 minutes is rejected outright. Installation tokens last
1 hour, are scoped to the installation, and allow 15k req/hr against a PAT's 5k. **In Actions use
`actions/create-github-app-token` rather than hand-rolling this.**

**OIDC** — no stored credential at all. With `permissions: id-token: write` the runner exposes a
token endpoint; exchange the result for a real cloud token (what `Azure/login@v3` does internally).

```bash
oidc=$(curl -sS --fail-with-body -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | jq -er .value)
```

**Azure CLI token** — `az account get-access-token --resource https://management.azure.com/
--query accessToken -o tsv`. The `--resource` audience must match the plane called (see [Azure
REST](#azure-rest-specifics)); "401 on a token that definitely works" is the wrong audience.

**Azure managed identity (IMDS)**:

```bash
token=$(curl -sS --fail-with-body -H "Metadata: true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fmanagement.azure.com%2F" \
  | jq -er .access_token)
```

`Metadata: true` is **mandatory** — it is the SSRF defence; without it, 400. `169.254.169.254` is
link-local, reachable only from inside the VM/VMSS: App Service and Container Apps instead use
`$IDENTITY_ENDPOINT` with an `X-IDENTITY-HEADER`, so read the env vars rather than hardcoding IMDS.
Add `&client_id=<guid>` when several user-assigned identities are attached or the request fails as
ambiguous. Never expose IMDS via a proxy or SSRF-able endpoint — that is credential compromise.

**Azure service principal** (last resort) — POST form fields `client_id`, `client_secret`,
`grant_type=client_credentials`, `scope=https://management.azure.com/.default` to
`https://login.microsoftonline.com/$TENANT/oauth2/v2.0/token`, reading `.access_token`; `.default`
is required by the v2.0 endpoint. A long-lived secret is what OIDC and managed identity eliminate.

## Not leaking tokens

- **Never put a token in a URL.** Query strings are logged by every proxy, load balancer, CDN and
  web server on the path, and reach browser history, `Referer` headers and APM traces —
  `-H "Authorization: Bearer $TOKEN"` is not. The single most important rule here.
- **Never pass a secret as a command-line argument** on a shared host — `ps aux` shows it to every
  user. Use env vars, `--netrc`, or config on stdin:
  `printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" | curl -sS --config - "$URL"`
- **Mask derived tokens immediately:** `echo "::add-mask::$token"`. `secrets.*` values are masked
  automatically; values you *compute* (an installation token, a parsed connection string) are
  **not**. Masking is literal substring matching — a base64 or URL-encoded form slips through.
- Never `set -x` around auth code and never `curl -v` in CI — both echo `Authorization`. Do not
  `echo` a response body that may contain a token (the App token response does); pipe into `jq`.

## Retries and backoff

Retry `408`, `429`, `5xx` and connection errors. Do **not** retry `400/401/403/404/409/422` —
those are deterministic; retrying burns rate limit and delays the real error.

```bash
request_with_backoff() {
  local url="$1" attempt=0 max=5 body code ra
  while :; do
    body=$(curl -sS -D /tmp/h -w '\n%{http_code}' -H "Authorization: Bearer $TOKEN" "$url") || true
    code=${body##*$'\n'}
    case "$code" in
      2*) printf '%s' "${body%$'\n'*}"; return 0 ;;
      408|429|5*) : ;;                                        # retryable
      *) echo "non-retryable $code: ${body%$'\n'*}" >&2; return 1 ;;
    esac
    (( ++attempt >= max )) && { echo "gave up after $max ($code)" >&2; return 1; }
    ra=$(awk 'tolower($1)=="retry-after:"{print $2}' /tmp/h | tr -d '\r')
    sleep "${ra:-$(awk -v a=$attempt 'BEGIN{srand();print (2^a)*(0.5+rand()/2)}')}"  # jittered 2^n
  done
}
```

- **Honour `Retry-After`** whenever present — ignoring it on a 429 is how a client gets
  hard-blocked. **Jitter is not optional**: pure `2^n` synchronizes a fleet into a herd.
- **429 and 5xx differ.** 429 means slow down and fix the call pattern; 5xx means the server broke
  — retry a few times then fail loudly; retrying for ten minutes hides an outage from alerting.
- **Only retry idempotent operations blindly.** A retried `POST` can double-create. Send an
  `Idempotency-Key` where supported, generated **once** and reused across retries of the same
  logical request; a fresh key per retry defeats the mechanism entirely.

## GitHub REST specifics

```bash
GH=(-sS --fail-with-body -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28" -H "Authorization: Bearer $GH_TOKEN")
curl "${GH[@]}" -X POST --data-binary '{"ref":"main","inputs":{"environment":"dev"}}' \
  https://api.github.com/repos/OWNER/REPO/actions/workflows/deploy.yml/dispatches
```

- **`X-GitHub-Api-Version: 2022-11-28`** is current. Send it explicitly — omitting it opts you
  into whatever the default becomes.
- **`workflow_dispatch` returns 204 with no body and no run ID.** To track the run you must poll
  `/actions/runs?event=workflow_dispatch&created=>TIMESTAMP` and correlate. This trips up every
  first attempt at "dispatch and wait".
- **Pagination is the `Link` header**, not a body cursor — never construct `?page=N`. After each
  `curl "${GH[@]}" -D /tmp/h "$url"`, take the next URL with
  `sed -n 's/.*<\([^>]*\)>; rel="next".*/\1/p' /tmp/h | tr -d '\r'` and loop until empty.
  `gh api --paginate` does this correctly and is the right answer wherever `gh` exists.
- Rate limits: `x-ratelimit-remaining`, `-reset` (epoch). On a 403/429 `remaining: 0` is the
  **primary** limit (wait for reset); a `retry-after` with remaining > 0 is the **secondary/abuse**
  limit (too concurrent). Search has its own 30/min limit; some endpoints are eventually consistent.

## Azure REST specifics

```bash
curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN" \
  "https://management.azure.com/subscriptions/$SUB/resourceGroups/$RG/providers/Microsoft.CognitiveServices/accounts/$NAME?api-version=2025-09-01"
```

- **`api-version` is required on every ARM call and is per resource type.** There is no global
  "latest". Omitting it returns `NoRegisteredProviderFound` or a 400 that never mentions the
  missing parameter; a version valid for a sibling type gives the same confusing error. Look it up
  per type — do not copy between resources.
- **Control plane and data plane are different hosts, tokens and version schemes.** ARM is
  `management.azure.com` (audience `https://management.azure.com/`); Key Vault data plane
  `<vault>.vault.azure.net` / `https://vault.azure.net`; Storage `<acct>.blob.core.windows.net` /
  `https://storage.azure.com/`; Cognitive Services `<acct>.cognitiveservices.azure.com` /
  `https://cognitiveservices.azure.com/`. Creating a vault is ARM, reading a secret is data plane —
  and `Contributor` on the vault does not grant secret reads (that is `Key Vault Secrets User`).
- **Async operations.** A `PUT`/`POST`/`DELETE` returning **201 or 202** has *accepted* the work,
  not completed it. Poll `Azure-AsyncOperation` (preferred — it returns a status object) or
  `Location`, respecting `Retry-After`:

  ```bash
  hdrs=$(curl -sS -D - -o /dev/null -X PUT -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" --data-binary @body.json "$ARM_URL?api-version=$AV")
  poll=$(awk 'tolower($1)=="azure-asyncoperation:"{print $2}' <<<"$hdrs" | tr -d '\r')
  while [ -n "$poll" ]; do
    st=$(curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN" "$poll" | jq -er .status)
    case "$st" in
      Succeeded) break ;;
      Failed|Canceled) echo "operation $st" >&2; exit 1 ;;
      *) sleep 5 ;;
    esac
  done
  ```

  Treating a 202 as success is the classic bug: the next step 404s on a resource still
  provisioning, and it reads as a race condition rather than a missing poll loop.
- Capture `x-ms-request-id` and `x-ms-correlation-request-id` — support asks for them. Errors are
  `{"error":{"code":…,"message":…}}`; branch on `.error.code`, as `.error.message` is prose.

## From ad-hoc curl to a committed smoke test

The curl you ran once to check the deploy *is* the smoke test. Commit it before you forget what
it verified.

```bash
#!/usr/bin/env bash
# scripts/smoke/aihub.sh — post-deploy verification. Exit 0 = healthy.
set -euo pipefail
: "${AIHUB_BASE_URL:?AIHUB_BASE_URL must be set}"
: "${AIHUB_TOKEN:?AIHUB_TOKEN must be set}"
fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }

check() {                             # name, path, expected status, optional jq assertion
  local name="$1" path="$2" want="$3" jq_expr="${4:-}" out code body
  out=$(curl -sS -w '\n%{http_code}' --max-time 10 \
        -H "Authorization: Bearer $AIHUB_TOKEN" "${AIHUB_BASE_URL}${path}") || fail "$name: curl $?"
  code=${out##*$'\n'}; body=${out%$'\n'*}
  [ "$code" = "$want" ] || fail "$name: expected HTTP $want, got $code — $body"
  [ -z "$jq_expr" ] || jq -e "$jq_expr" >/dev/null <<<"$body" \
    || fail "$name: body assertion failed ($jq_expr) — $body"
  echo "ok  $name ($code)"
}

check "health"    "/healthz"           200 '.status == "healthy"'
check "providers" "/v1/providers"      200 '.providers | length > 0'
check "authz"     "/v1/admin/settings" 403     # the deny path, not just the allow path
echo "SMOKE PASS"
```

Wire it with `env: { AIHUB_BASE_URL: '${{ steps.deploy.outputs.appUrl }}', AIHUB_TOKEN:
'${{ secrets.SMOKE_TOKEN }}' }` and `run: ./scripts/smoke/aihub.sh`. Reading the base URL from the
**deployment output** makes it a seam test: rename the IaC output and `${VAR:?}` fires instead of
the script silently probing nothing.

What makes it a test rather than a script: `set -euo pipefail` (`pipefail` so a failure inside a
pipe isn't swallowed by a successful `jq`); `${VAR:?message}` so missing config fails immediately
instead of sending `Bearer` and getting a confusing 401; an **explicit expected status per check
including a negative case** (a suite that only asserts 200s won't notice authorization stopped
working); `--max-time` everywhere; and messages naming the broken thing. Run it after every deploy
*and* against production on a schedule — deploy-time-only never detects drift.

## When to stop using curl

Switch to the SDK (`azure-identity` + `azure-mgmt-*`, Octokit) when any of these holds: auth needs
refresh or caching (hand-rolled JWT signing is where credential bugs live; `DefaultAzureCredential`
covers CLI/managed identity/OIDC/env plus expiry); more than ~3 chained calls, or parsing beyond a
single `jq` extraction; pagination over a large collection (`Link` loops in bash are right about
half the time); long-running operations (SDK pollers implement `Azure-AsyncOperation` including
edge cases you won't hit until production); structured error handling or partial-batch failure; or
the logic needs tests — mocking HTTP is easy, testing a bash pipeline is not.

Keep curl for one-shot smoke tests, health checks, webhook fires, minimal containers with no
runtime, and reproducing a bug in a report. The failure mode isn't "used curl", it's "grew a
300-line bash client nobody can test." Middle ground first: `gh api --paginate <path> --jq …` and
`az rest --method get --url "$ARM_URL?api-version=2021-04-01"` give you auth, pagination and
correct headers for free while staying a one-liner.
