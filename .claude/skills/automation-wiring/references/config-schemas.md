# Config Schema Reference

JSON, YAML, `.env`, and plain-text manifests — designed so the code that reads them and the file
that ships cannot drift apart.

## Contents

- [Env-name indirection](#the-env-name-indirection-pattern) · [Schema-first](#schema-first) · [Drift test](#the-drift-test) · [JSON vs YAML](#json-vs-yaml) · [YAML traps](#yaml-traps)
- [.env](#env-conventions-and-limits) · [Layering](#layering-and-precedence) · [Validation](#validation-and-failure-mode) · [Manifests](#plain-text-manifests) · [Versioning](#versioning-and-migration)

## The env-name indirection pattern

Config files get committed, pasted into tickets, and mounted into containers. A config file must
never hold a secret **value** — it holds the *name of the place the value comes from*. Before,
one `git add -A` from an incident:

```json
{ "providers": [ { "name": "openai", "apiKey": "sk-proj-abc123...", "model": "gpt-4o" } ] }
```

After — safe to commit, and the missing-secret failure becomes explicit:

```json
{
  "$schema": "./providers.schema.json",
  "schemaVersion": 2,
  "providers": [
    { "name": "openai",    "apiKeyEnv": "OPENAI_API_KEY",    "model": "gpt-4o" },
    { "name": "anthropic", "apiKeyEnv": "ANTHROPIC_API_KEY", "model": "claude-opus-4" }
  ]
}
```

```python
key = os.environ.get(provider["apiKeyEnv"])
if not key:
    raise ConfigError(f"Provider {provider['name']!r} requires env var "
                      f"{provider['apiKeyEnv']!r}, which is unset — set it or drop the provider.")
```

What this buys: a diffable, committable config; an error naming the exact variable to set (compare
a bare `401`); **the same file in every environment**; and nothing for secret scanners to find.
Extend it to non-secret environment-shaped values (`"endpointEnv"`, `"keyVaultSecret"`), keeping
the `*Env`/`*Ref`/`*SecretName` suffix convention repo-wide so a raw value stands out in review.

## Schema-first

Pick **one** artifact as the source of truth; two hand-maintained sources is zero.

**Option 1 — JSON Schema**, best when several languages read the config:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object", "additionalProperties": false,
  "required": ["schemaVersion", "providers"],
  "properties": {
    "schemaVersion": { "type": "integer", "const": 2 },
    "providers": { "type": "array", "minItems": 1, "items": {
      "type": "object", "additionalProperties": false,
      "required": ["name", "apiKeyEnv", "model"],
      "properties": {
        "name":      { "type": "string", "pattern": "^[a-z][a-z0-9-]*$" },
        "apiKeyEnv": { "type": "string", "pattern": "^[A-Z][A-Z0-9_]*$" },
        "model": { "type": "string" }, "timeoutMs": { "type": "integer", "minimum": 100 }
      }}}
  }
}
```

`"additionalProperties": false` is the load-bearing line: without it a typo'd key (`"apikeyEnv"`)
validates cleanly and is silently ignored — the config looks fine and the behaviour is wrong,
which is the most common config bug there is. A `"$schema"` key in the *instance* file (relative
path or URL) gives VS Code live validation and completion with zero setup.

**Option 2 — a typed class**, best when one language owns the config:

```python
class Provider(BaseModel):
    model_config = ConfigDict(extra="forbid")     # == additionalProperties: false
    name: str = Field(pattern=r"^[a-z][a-z0-9-]*$")
    api_key_env: str = Field(alias="apiKeyEnv")
    timeout_ms: int = Field(default=30_000, alias="timeoutMs", ge=100)
```

`extra="forbid"` (pydantic v2) / `.strict()` (zod) / a validating `IValidateOptions<T>` (C# Options)
are the equivalents — turn them on, since silently ignoring unknown keys is most binders' default
and it is the wrong one. Then *generate* the JSON Schema from the class (`model_json_schema()`,
`zod-to-json-schema`) and commit the output, so editors keep completion and the two cannot diverge.

## The drift test

A schema applied only to test fixtures proves nothing. The test must load **the file that ships**:

```python
CONFIG = Path(__file__).parents[1] / "config" / "providers.json"

def test_shipped_config_matches_schema():          # renames break the build, not prod
    ProvidersConfig.model_validate_json(CONFIG.read_text())

def test_every_referenced_env_var_is_documented():
    cfg = ProvidersConfig.model_validate_json(CONFIG.read_text())
    declared = {l.split("=", 1)[0].strip()
                for l in (Path(__file__).parents[1] / ".env.template").read_text().splitlines()
                if l.strip() and not l.startswith("#")}
    missing = {p.api_key_env for p in cfg.providers} - declared
    assert not missing, f"Config references undocumented env vars: {sorted(missing)}"
```

The second is the seam test — it catches "someone added a provider and nobody told ops which
variable to set." Write one per producer/consumer pair: config key → env var, config key → Bicep
parameter, workflow `secrets.X` → `.env.template`. Run them in the normal unit test job.

## JSON vs YAML

**JSON for anything a program writes or a schema binds; YAML only where a human maintains it or a
tool mandates it** (Actions, k8s, Helm, compose, OpenAPI). YAML round-trips destroy comments and
key order, so never machine-write it; conversely JSON has no comments and no multi-line strings,
and YAML's ambiguity (below) is substantial. Mitigate the comment gap with a `"description"`
convention, or JSONC where the reader supports it (`tsconfig.json`, VS Code settings; .NET
`appsettings` does **not**). No third format — TOML only where the ecosystem already uses it.

## YAML traps

```yaml
countries: [DE, FR, NO, GB]   # "NO" → boolean false: the Norway problem
enabled: on                   # → true, not the string "on"
version: 1.20                 # → float 1.2, trailing zero gone
build: 010                    # → 8 in YAML 1.1 (octal), 10 in some 1.2 parsers
mac: 12:34:56                 # → base-60 integer in YAML 1.1
port: "8080"                  # quoted: stays a string
```

**The Norway problem.** YAML 1.1 (PyYAML and much tooling) reads `y Y yes no n N on off true false`
and case variants as booleans; YAML 1.2 narrowed that to `true`/`false` and Go's yaml.v3 and JS
`js-yaml` default to 1.2 — **the same file parses differently in Python and Go**. Quote regardless.

- **Tabs are illegal for indentation** and the parse error points several lines away. Configure the
  editor plus `.editorconfig indent_style = space`.
- **Duplicate keys** are an error per spec; most parsers silently take the last, so two `env:`
  blocks in a long file quietly drop the first. `yamllint` catches it, `yaml.safe_load` does not.
- **Anchors/aliases** (`&defaults`, `*defaults`, `<<:` merge) do not work across files, **GitHub
  Actions does not support them at all**, and deep alias graphs are a DoS vector.
- **Block scalars:** `|` keeps newlines, `>` folds them into spaces, `|-` strips the trailing
  newline. For a script body or a PEM block use `|` or `|-` — `>` corrupts them silently.
- **Empty values are `null`, not `""`.** `foo:` yields `None`, so `config["foo"].strip()` crashes
  on a key that looks set.

## .env conventions and limits

```bash
# .env.template — COMMITTED. Names and comments only, never values.
AZURE_OPENAI_ENDPOINT=     # e.g. https://helios-dev.cognitiveservices.azure.com/
# Required. Get from: az keyvault secret show --vault-name kv-helios --name openai-key
OPENAI_API_KEY=
HELIOS_TIMEOUT_MS=30000    # optional; defaults to 30000
```

- **`.env.template` committed, `.env` gitignored, always** — ignore `.env` and `.env.*`, then
  `!.env.template`. The template documents what the app needs; assert on it in the drift test.
- No nesting: `A__B=1` is a *convention* the .NET config provider interprets; a plain `os.environ`
  reader sees no hierarchy. Everything is a string — `DEBUG=false` is truthy. Never coerce with `bool()`.
- **Quoting is not standardized.** `python-dotenv`, node `dotenv`, Docker Compose's `env_file` and
  `set -a; source .env` all differ on quotes, escapes, mid-line `#`, and multi-line values;
  `PASSWORD=abc#123` may truncate at the `#`. Keep values simple; base64 anything exotic. Docker's
  `env_file` also does **not** expand `A=${B}` while a shell `source` does — same file, different result.
- `.env` is for local development. CI uses repository secrets; production uses Key Vault or
  container app secrets. A `.env` in production is an escaped local convenience.

## Layering and precedence

State the order — `built-in defaults < config file < environment variables < CLI flags` — in the
README, and implement it in exactly one place:

```python
def load_config(path: Path, argv: Sequence[str]) -> Config:
    data = DEFAULTS.copy()
    if path.exists():
        data |= json.loads(path.read_text())
    data |= _from_env(prefix="HELIOS_")
    data |= _from_cli(argv)
    return Config.model_validate(data)      # validate ONCE, after merging
```

- Validate the **merged** result, not each layer — a layer legitimately supplies a partial object;
  only the merge must be complete.
- Decide and document whether nested merging is **deep or shallow**, and whether lists **replace or
  append**. Both are defensible; unstated is not. Replace is less surprising.
- Ship a `--print-config` dumping resolved values with secrets redacted and ideally the origin of
  each; it turns multi-hour debugging into one command. Do not add a fifth layer.

## Validation and failure mode

```python
data = yaml.safe_load(f)            # NEVER yaml.load — it can instantiate objects (RCE)
validator = Draft202012Validator(json.loads(Path("config.schema.json").read_text()))
errors = sorted(validator.iter_errors(data), key=lambda e: e.json_path)
if errors:
    for e in errors:                # report ALL of them, not just the first
        print(f"  {e.json_path}: {e.message}", file=sys.stderr)
    raise SystemExit(2)             # dedicated code: "will never start" ≠ "crashed, retry"
```

- **`yaml.safe_load`, never `yaml.load`.** The latter builds arbitrary objects from
  `!!python/object/apply:os.system` — same class as `pickle`/`eval`. Config files are untrusted.
- **Fail loudly at startup, not lazily at first use.** Validate everything in the first hundred
  milliseconds; a provider that only errors on first call turns a deploy failure into a 3am page.
- Report every error at once with a JSON path (`iter_errors`, not `validate`) — debugging config
  one error per run is miserable.
- Distinguish "invalid" (crash — the operator wrote something wrong) from "absent optional" (use
  the default, log at info). Never degrade silently on invalid input.

## Plain-text manifests

- **`requirements.txt`** — `#` comments, `-r other.txt` includes, `-e .` editable. Pin exactly
  (`==`) for applications and lock with hashes (`pip-compile --generate-hashes`, or `uv lock`);
  range-pin only for libraries. Markers are part of the line: `pywin32==306; sys_platform=="win32"`.
- **`.gitignore`** — order matters, **last match wins**. Leading `/` anchors, trailing `/` matches
  directories, `**` crosses them, `!` negates. **A negation cannot re-include a file inside an
  excluded directory**: `logs/` + `!logs/keep.md` fails (git never descends); use `logs/*` instead.
- **`CODEOWNERS`** — gitignore-style patterns, **last matching rule wins** (the opposite of most
  intuitions), so general rules first, specific last. Owners without write access are **silently
  ignored** — reviewers just never get requested. Wire `/repos/{o}/{r}/codeowners/errors` into CI.
- **`.gitattributes`** — `* text=auto` plus explicit `*.sh text eol=lf` stops CRLF from breaking
  shell scripts and Docker builds on Windows checkouts. A real CI failure, not hygiene.

## Versioning and migration

Add a version field on day one; retrofitting requires guessing at old files.

```python
MIGRATIONS = {1: _v1_to_v2}          # keyed by the version being migrated FROM

def load(raw: dict) -> Config:
    v = raw.get("schemaVersion", 1)  # absent == oldest
    if v > CURRENT:
        raise ConfigError(f"schemaVersion {v} is newer than this build supports ({CURRENT}).")
    while v < CURRENT:
        raw = MIGRATIONS[v](raw)
        v = raw["schemaVersion"]
    return Config.model_validate(raw)
```

- Bump only for **breaking** changes: removing or renaming a key, changing a type, changing a
  value's meaning. Adding an optional key with a safe default is not breaking.
- Migrate **forward on read**, in code; keep the migration functions forever — they are small.
- Reject newer-than-supported explicitly. The default behaviour — ignoring unknown fields — means a
  new-format file loads with half its settings missing.
- For a user-editable file, write the migrated version back once and log it. For a committed file,
  **warn instead of rewriting** so the change lands in a reviewed commit.
