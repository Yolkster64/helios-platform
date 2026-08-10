# Config Schema Reference

JSON, YAML, `.env`, and plain-text manifests — designed so the code that reads them and the
file that ships cannot drift apart.

## Contents

- [Env-name indirection](#the-env-name-indirection-pattern) · [Schema-first](#schema-first) · [The drift test](#the-drift-test)
- [JSON vs YAML](#json-vs-yaml) · [YAML traps](#yaml-traps) · [.env](#env-conventions-and-limits)
- [Layering](#layering-and-precedence) · [Validation](#validation-and-failure-mode)
- [Plain-text manifests](#plain-text-manifests) · [Versioning](#versioning-and-migration)

## The env-name indirection pattern

Config files get committed, pasted into tickets, and mounted into containers. A config file
must never hold a secret **value** — it holds the *name of the place the value comes from*.

Before, one `git add -A` from an incident:

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
    raise ConfigError(
        f"Provider {provider['name']!r} requires env var {provider['apiKeyEnv']!r}, "
        f"which is unset. Set it or remove the provider from config."
    )
```

What this buys: the config is diffable and committable; the error names the exact variable
to set (compare to a bare `401`); **the same file works in every environment**, which is
what kills "works on my machine" for config; and secret scanners have nothing to find, so
nobody is trained to click "allow".

Extend it to non-secret environment-shaped values (`"endpointEnv"`, `"keyVaultSecret"`).
Keep the suffix convention (`*Env`, `*Ref`, `*SecretName`) consistent repo-wide so a
reviewer spots a raw value instantly.

## Schema-first

Pick **one** artifact as the source of truth. Two hand-maintained sources is zero.

**Option 1 — JSON Schema.** Best when several languages read the config.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["schemaVersion", "providers"],
  "additionalProperties": false,
  "properties": {
    "schemaVersion": { "type": "integer", "const": 2 },
    "providers": {
      "type": "array", "minItems": 1,
      "items": {
        "type": "object",
        "required": ["name", "apiKeyEnv", "model"],
        "additionalProperties": false,
        "properties": {
          "name":      { "type": "string", "pattern": "^[a-z][a-z0-9-]*$" },
          "apiKeyEnv": { "type": "string", "pattern": "^[A-Z][A-Z0-9_]*$" },
          "model":     { "type": "string" },
          "timeoutMs": { "type": "integer", "minimum": 100, "default": 30000 }
        }
      }
    }
  }
}
```

`"additionalProperties": false` is the load-bearing line. Without it a typo'd key
(`"apikeyEnv"`) validates cleanly and is silently ignored — the config looks fine and the
behaviour is wrong. This is the most common config bug there is.

A `"$schema"` key in the *instance* file (relative path or URL) gives VS Code live
validation and completion with zero setup.

**Option 2 — a typed class.** Best when one language owns the config.

```python
class Provider(BaseModel):
    model_config = ConfigDict(extra="forbid")     # == additionalProperties: false
    name: str = Field(pattern=r"^[a-z][a-z0-9-]*$")
    api_key_env: str = Field(alias="apiKeyEnv")
    model: str
    timeout_ms: int = Field(default=30_000, alias="timeoutMs", ge=100)
```

`extra="forbid"` (pydantic v2) / `.strict()` (zod) / a validating `IValidateOptions<T>` (C#
Options) are the equivalents. Turn them on — silently ignoring unknown keys is the default
in most binders and it is the wrong default. Then *generate* the JSON Schema from the class
(`model_json_schema()`, `zod-to-json-schema`) and commit the output so editors still get
completion and the two cannot diverge.

## The drift test

A schema applied only to test fixtures proves nothing. The test must load **the file that
ships**:

```python
CONFIG = Path(__file__).parents[1] / "config" / "providers.json"

def test_shipped_config_matches_schema():
    """Renames break the build, not prod."""
    ProvidersConfig.model_validate_json(CONFIG.read_text())

def test_every_referenced_env_var_is_documented():
    cfg = ProvidersConfig.model_validate_json(CONFIG.read_text())
    template = (Path(__file__).parents[1] / ".env.template").read_text()
    declared = {l.split("=", 1)[0].strip() for l in template.splitlines()
                if l.strip() and not l.startswith("#")}
    missing = {p.api_key_env for p in cfg.providers} - declared
    assert not missing, f"Config references undocumented env vars: {sorted(missing)}"
```

The second test is the seam test — it catches "someone added a provider and nobody told ops
which variable to set." Write the equivalent for every producer/consumer pair: config key →
env var, config key → Bicep parameter, workflow `secrets.X` → `.env.template` entry. Run
them in the normal unit test job, not a separate "config lint" job people can skip.

## JSON vs YAML

| | JSON | YAML |
|---|---|---|
| Machine-written | ✅ | ❌ (round-trips destroy comments and order) |
| Schema-bound app config | ✅ | ok |
| Human-edited, comment-heavy | ❌ (no comments) | ✅ |
| Long multi-line strings | ❌ | ✅ |
| Ambiguity | none | substantial |

**JSON for anything a program writes or a schema binds; YAML only where a human maintains it
or a tool mandates it** (Actions, k8s, Helm, compose, OpenAPI). JSON's lack of comments is a
real cost — mitigate with a `"description"` convention, or JSONC where the reader supports
it (`tsconfig.json`, VS Code settings; .NET `appsettings` does **not**).

Don't introduce a third format. TOML where the ecosystem already uses it (`pyproject.toml`);
elsewhere it adds a parser dependency and bugs nobody has seen before.

## YAML traps

**The Norway problem.** YAML 1.1 (PyYAML, and much tooling) treats these as booleans:
`y Y yes no n N on off true false` and their case variants.

```yaml
countries: [DE, FR, NO, GB]    # NO parses as boolean false
enabled: on                    # true, not the string "on"
```

YAML 1.2 narrowed this to `true`/`false`, and Go's yaml.v3 / JS `js-yaml` default to 1.2 —
so **the same file parses differently in Python and Go**. Quote regardless.

**Numeric coercion.**

```yaml
version: 1.20      # float 1.2 — trailing zero gone
build: 010         # 8 in YAML 1.1 (octal), 10 in some 1.2 parsers
mac: 12:34:56      # base-60 integer in YAML 1.1
port: "8080"       # quote if the consumer wants a string
```

Quote every version number, zero-padded ID, and colon-separated value. Always.

**Tabs are illegal for indentation** and the parse error points several lines away.
Configure the editor plus `.editorconfig indent_style = space`.

**Duplicate keys** are an error per spec; most parsers silently take the last. Two `env:`
blocks in a long file quietly drop the first. `yamllint` catches it, `yaml.safe_load` does
not.

**Anchors/aliases** (`&defaults`, `*defaults`, `<<:` merge) do not work across files,
**GitHub Actions does not support them at all**, and deep alias graphs are a DoS vector.

**Block scalars:** `|` keeps newlines, `>` folds them into spaces, `|-` strips the trailing
newline. For a script body or a PEM block use `|` or `|-` — `>` corrupts them silently.

**Empty values are `null`, not `""`.** `foo:` yields `None`, so `config["foo"].strip()`
crashes on a key that looks set.

## .env conventions and limits

```bash
# .env.template — COMMITTED. Names and comments only, never values.
# Azure AI Foundry endpoint, e.g. https://helios-dev.cognitiveservices.azure.com/
AZURE_OPENAI_ENDPOINT=
# Required. Get from: az keyvault secret show --vault-name kv-helios --name openai-key
OPENAI_API_KEY=
HELIOS_TIMEOUT_MS=30000    # optional; defaults to 30000
```

```gitignore
.env
.env.*
!.env.template
```

- **`.env.template` committed, `.env` gitignored, always.** The template documents what the
  app needs — assert on it in the drift test above.
- No nesting. `A__B=1` double-underscore is a *convention* the .NET config provider
  interprets; a plain `os.environ` reader sees no hierarchy.
- Everything is a string. `DEBUG=false` is the truthy string `"false"`. Never
  `bool(os.environ["DEBUG"])`.
- **Quoting is not standardized.** `python-dotenv`, node `dotenv`, Docker Compose's
  `env_file`, and `set -a; source .env` all differ on quotes, escapes, mid-line `#`, and
  multi-line values. `PASSWORD=abc#123` may truncate at the `#`. Keep values simple; base64
  anything with special characters or newlines.
- Docker's `env_file` does **not** expand variables (`A=${B}` stays literal); a shell
  `source` does. Same file, different result.
- `.env` is for local development. CI uses repository secrets; production uses Key Vault or
  container app secrets. A `.env` in production is an escaped local convenience.

## Layering and precedence

State the order in the README and implement it in exactly one place:

```
built-in defaults  <  config file  <  environment variables  <  CLI flags
```

```python
def load_config(path: Path, argv: Sequence[str]) -> Config:
    data = DEFAULTS.copy()
    if path.exists():
        data |= json.loads(path.read_text())
    data |= _from_env(prefix="HELIOS_")
    data |= _from_cli(argv)
    return Config.model_validate(data)      # validate ONCE, after merging
```

- Validate the **merged** result, not each layer — a layer legitimately supplies a partial
  object; only the merge must be complete.
- Decide and document whether nested merging is **deep or shallow**, and whether lists
  **replace or append**. Both are defensible; unstated is not. Replace is less surprising.
- Ship a `--print-config` that dumps resolved values with secrets redacted, ideally with the
  origin of each. This turns multi-hour debugging into one command.
- Do not add a fifth layer. Each multiplies the states a support question can be in.

## Validation and failure mode

```python
data = yaml.safe_load(f)            # NEVER yaml.load — it can instantiate objects (RCE)

validator = Draft202012Validator(json.loads(Path("config.schema.json").read_text()))
errors = sorted(validator.iter_errors(data), key=lambda e: e.json_path)
if errors:
    for e in errors:                # report ALL of them, not just the first
        print(f"  {e.json_path}: {e.message}", file=sys.stderr)
    raise SystemExit(2)
```

- **`yaml.safe_load`, never `yaml.load`.** The latter can construct arbitrary Python objects
  from `!!python/object/apply:os.system`. Same class: `pickle`, `eval`, `BinaryFormatter`.
  Treat every config file as untrusted input, because eventually one is.
- **Fail loudly at startup, not lazily at first use.** Parse and validate everything in the
  first hundred milliseconds. A bad provider that only errors when someone finally calls it
  turns a deploy-time failure into a 3am page.
- Report every error at once with a JSON path (`iter_errors`, not `validate`). Debugging
  config one error per run is miserable.
- Distinguish "invalid" (crash — the operator wrote something wrong) from "absent optional"
  (use the default, log at info). Never degrade silently on invalid input.
- Use a dedicated exit code (2) so a supervisor can tell "will never start" from "crashed,
  retry".

## Plain-text manifests

Formats mandated by tooling, with rules worth knowing exactly:

- **`requirements.txt`** — `#` comments, `-r other.txt` includes, `-e .` editable. Pin
  exactly (`==`) for applications and lock with hashes (`pip-compile --generate-hashes`, or
  `uv lock`); range-pin only for libraries. Markers are part of the line:
  `pywin32==306; sys_platform == "win32"`.
- **`.gitignore`** — order matters, **last match wins**. Leading `/` anchors, trailing `/`
  matches directories, `**` crosses directories, `!` negates. **A negation cannot re-include
  a file inside an excluded directory** — `logs/` + `!logs/keep.md` fails because git never
  descends into `logs/`. Use `logs/*` + `!logs/keep.md`.
- **`CODEOWNERS`** — gitignore-style patterns, **last matching rule wins** (the opposite of
  most people's intuition), so general rules first, specific last. Owners without write
  access are **silently ignored** — no error, reviewers just never get requested. Wire
  `gh api /repos/{o}/{r}/codeowners/errors` into CI.
- **`.gitattributes`** — `* text=auto` plus explicit `*.sh text eol=lf` prevents CRLF from
  breaking shell scripts and Docker builds on Windows checkouts. A real CI failure, not
  hygiene.

## Versioning and migration

Add a version field on day one; retrofitting requires guessing at old files.

```python
MIGRATIONS = {1: _v1_to_v2}          # keyed by the version being migrated FROM

def load(raw: dict) -> Config:
    v = raw.get("schemaVersion", 1)  # absent == oldest
    if v > CURRENT:
        raise ConfigError(f"schemaVersion {v} is newer than this build supports "
                          f"({CURRENT}). Upgrade the application.")
    while v < CURRENT:
        raw = MIGRATIONS[v](raw)
        v = raw["schemaVersion"]
    return Config.model_validate(raw)
```

- Bump only for **breaking** changes: removing or renaming a key, changing a type, changing
  a value's meaning. Adding an optional key with a safe default is not breaking.
- Migrate **forward on read**, in code, and keep the migration functions forever. They are
  small and someone will open a two-year-old file.
- Reject newer-than-supported explicitly. The default behaviour — ignoring unknown fields —
  means a new-format file loads with half its settings missing.
- For a user-editable file, write the migrated version back once and log it. For a
  committed file, **warn instead of rewriting** so the change lands in a reviewed commit.
