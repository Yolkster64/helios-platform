using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace HELIOS.Mcp;

/// <summary>
/// Dependency-free JSON Schema (draft 2020-12) validator for the keyword subset the
/// repo's config/schemas/*.schema.json files use. The twin of the built-in engine in
/// scripts/validation/validate_config_schemas.py: same keywords, same refusal of a
/// schema that uses anything outside the subset, and the same error wording, so the
/// helios_config_validate tool and the CI gate report identically. No package is
/// pulled in on purpose: Directory.Packages.props carries no schema library, and the
/// subset is small enough to own.
/// </summary>
internal static class JsonSchemaLite
{
    internal sealed record Issue(string Path, string Message);

    /// <summary>Thrown for a schema the validator cannot honour (unknown keyword, dangling $ref).</summary>
    internal sealed class SchemaException : Exception
    {
        public SchemaException(string message) : base(message)
        {
        }
    }

    private static readonly HashSet<string> Annotations = new(StringComparer.Ordinal)
    {
        "$schema", "$id", "$comment", "$defs", "definitions", "title", "description",
        "default", "examples", "deprecated", "readOnly", "writeOnly",
    };

    private static readonly HashSet<string> Supported = new(StringComparer.Ordinal)
    {
        "$ref", "type", "enum", "const", "properties", "patternProperties",
        "additionalProperties", "propertyNames", "required", "minProperties", "maxProperties",
        "items", "contains", "minItems", "maxItems", "uniqueItems", "minLength", "maxLength",
        "pattern", "format", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
        "allOf", "anyOf", "oneOf", "not", "if", "then", "else",
    };

    private static readonly string[] TypeNames =
    {
        "null", "boolean", "object", "array", "number", "integer", "string",
    };

    private static readonly TimeSpan RegexTimeout = TimeSpan.FromSeconds(2);

    /// <summary>Validates <paramref name="instance"/>; an empty list means valid.</summary>
    internal static IReadOnlyList<Issue> Validate(JsonElement schemaRoot, JsonElement instance)
    {
        var validator = new Validator(schemaRoot);
        // The self-check runs on every validation, like the Python engine's MiniValidator: a
        // malformed keyword value or an unsafe pattern is a SchemaException before any instance
        // keyword is evaluated, never an InvalidOperationException from the middle of a walk.
        validator.CheckSchema();
        validator.ResetBudget();   // the walk below gets the whole budget, not what the check left
        var issues = new List<Issue>();
        validator.Validate(schemaRoot, instance, "$", issues);
        return issues;
    }

    /// <summary>
    /// A JSON number's identity, exactly: 191 and 191.0 share it. Semantic rules outside this
    /// class compare numbers with it so they read a value the way schema validation does.
    /// </summary>
    internal static string NumberKey(JsonElement number) => Validator.CanonicalNumberFor(number);

    /// <summary>True when the token is a real, finite JSON number every consumer can hold.</summary>
    /// <remarks>
    /// Double range is one half of it; the other is an exponent this validator can order exactly.
    /// The Python engine refuses both while READING a file (float() gives inf, decimal.Decimal
    /// refuses the exponent), so a token failing either test makes one manifest valid here and
    /// unreadable there.
    /// </remarks>
    internal static bool IsFiniteNumber(JsonElement number) =>
        number.ValueKind == JsonValueKind.Number && number.TryGetDouble(out var value) && double.IsFinite(value)
        && Validator.IsExactNumber(number);

    /// <summary>
    /// The value of a whole-number token, however it is spelled: 64, 64.0 and 6.4e1 are the same
    /// 64, which is what PowerShell's [int] cast and the Python engine both read. TryGetInt64 alone
    /// answers false for the last two, so a semantic rule using it would silently count zero.
    /// </summary>
    internal static bool TryGetWholeNumber(JsonElement number, out long value) =>
        Validator.TryGetWholeNumberFor(number, out value);

    /// <summary>Rejects a schema that uses a keyword outside the supported subset.</summary>
    internal static void CheckSchema(JsonElement schemaRoot) => new Validator(schemaRoot).CheckSchema();

    private sealed class Validator
    {
        private readonly JsonElement _root;
        private readonly Dictionary<string, Regex> _regexes = new(StringComparer.Ordinal);

        // A $ref that resolves back to itself without descending into the instance ("$ref": "#",
        // or two $defs pointing at each other) would recurse until the process died with an
        // uncatchable StackOverflowException — the MCP server with it. Real schemas nest a few
        // dozen levels at most; past this the schema is the problem and says so.
        private const int MaxDepth = 256;
        private int _depth;
        private int _walkDepth;

        // One instance may cost this many keyword evaluations. An acyclic $defs chain whose allOf
        // duplicates the next $ref doubles the work at every level, so the depth guard never fires
        // while the walk grows exponentially — and this server answers one request per process, so
        // nothing else would stop it. A ceiling on total work, not on nesting; the Python twin
        // carries the same one (_MAX_EVALUATIONS).
        private const int MaxEvaluations = 200_000;
        private int _evaluations;

        public void ResetBudget() => _evaluations = 0;

        private void CountEvaluation(string path)
        {
            if (++_evaluations > MaxEvaluations)
            {
                throw new SchemaException(
                    $"{path}: this schema costs more than {MaxEvaluations} keyword evaluations for one " +
                    "instance — an allOf that repeats the $ref below it doubles the work at every level");
            }
        }

        public Validator(JsonElement root)
        {
            _root = root;
        }

        // -- schema self-check -------------------------------------------------------

        public void CheckSchema()
        {
            _evaluations = 0;
            _walkDepth = 0;
            WalkSchema(_root, "#");
        }

        private void WalkSchema(JsonElement node, string where)
        {
            // CountEvaluation bounds the NUMBER of schema nodes, not the depth of the call stack:
            // a few thousand nested `not` or `items` reach this recursion before the guarded
            // instance walk ever runs, and a StackOverflowException cannot be caught — it takes
            // the MCP process with it. The Python twin guards its own schema walk at the same
            // depth (_walk_schema), so both give a verdict instead of dying.
            if (++_walkDepth > MaxDepth)
            {
                _walkDepth--;
                throw new SchemaException(
                    $"{where}: schema nesting deeper than {MaxDepth} levels — more structure than any manifest schema needs");
            }
            try
            {
                WalkSchemaHere(node, where);
            }
            finally
            {
                _walkDepth--;
            }
        }

        private void WalkSchemaHere(JsonElement node, string where)
        {
            CountEvaluation(where);
            if (node.ValueKind is JsonValueKind.True or JsonValueKind.False)
            {
                return;
            }
            if (node.ValueKind != JsonValueKind.Object)
            {
                throw new SchemaException($"{where}: a schema must be an object or a boolean");
            }

            foreach (var property in node.EnumerateObject())
            {
                var key = property.Name;
                var value = property.Value;
                if (key == "$schema" && where != "#")
                {
                    // The Python engine refuses this so python-jsonschema cannot hand the subtree
                    // back to a validator without its regex and number rules. Nothing here would
                    // re-select an engine, but a schema must not be usable through one path and
                    // refused by the other: one dialect, declared once, at the root.
                    throw new SchemaException($"{where}/$schema: a dialect may only be declared at the root of a schema");
                }
                if (Annotations.Contains(key))
                {
                    if (key is "$defs" or "definitions" && value.ValueKind == JsonValueKind.Object)
                    {
                        foreach (var def in value.EnumerateObject())
                        {
                            WalkSchema(def.Value, $"{where}/{key}/{def.Name}");
                        }
                    }
                    continue;
                }
                if (!Supported.Contains(key))
                {
                    throw new SchemaException(
                        $"{where}: keyword '{key}' is not implemented by the built-in validator; " +
                        "extend JsonSchemaLite (and validate_config_schemas.py) or drop the keyword");
                }

                switch (key)
                {
                    case "properties":
                    case "patternProperties":
                        if (value.ValueKind != JsonValueKind.Object)
                        {
                            throw new SchemaException($"{where}/{key}: must be an object");
                        }
                        foreach (var sub in value.EnumerateObject())
                        {
                            if (key == "patternProperties")
                            {
                                // The KEY is itself a regex, and a walk of the subschemas never
                                // reaches it: against an instance with no properties nothing would
                                // ever compile "[", and the schema would pass as usable.
                                using var keyDocument = JsonDocument.Parse($"\"{JsonEncodedText.Encode(sub.Name)}\"");
                                Compile(keyDocument.RootElement.Clone(), $"{where}/{key}/{sub.Name}");
                            }
                            WalkSchema(sub.Value, $"{where}/{key}/{sub.Name}");
                        }
                        break;
                    case "additionalProperties":
                    case "propertyNames":
                    case "items":
                    case "contains":
                    case "not":
                    case "if":
                    case "then":
                    case "else":
                        WalkSchema(value, $"{where}/{key}");
                        break;
                    case "allOf":
                    case "anyOf":
                    case "oneOf":
                        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() == 0)
                        {
                            throw new SchemaException($"{where}/{key}: must be a non-empty array");
                        }
                        var index = 0;
                        foreach (var sub in value.EnumerateArray())
                        {
                            WalkSchema(sub, $"{where}/{key}/{index++}");
                        }
                        break;
                    case "type":
                        if (value.ValueKind != JsonValueKind.String
                            && (value.ValueKind != JsonValueKind.Array
                                || value.GetArrayLength() == 0
                                || value.EnumerateArray().Any(name => name.ValueKind != JsonValueKind.String)))
                        {
                            throw new SchemaException($"{where}/type: must be a type name or a non-empty array of type names");
                        }
                        foreach (var name in TypeList(value))
                        {
                            if (Array.IndexOf(TypeNames, name) < 0)
                            {
                                throw new SchemaException($"{where}/type: unknown type '{name}'");
                            }
                        }
                        break;
                    case "pattern":
                        Compile(value, where);
                        break;
                    case "$ref":
                        Resolve(value, where);
                        break;
                    // Keyword VALUES are checked here, once, so a malformed schema is a SchemaException
                    // ("not usable" on the tool) instead of an InvalidOperationException from GetInt32
                    // deep inside validation. Same rules as the Python engine's _walk_schema.
                    case "minLength":
                    case "maxLength":
                    case "minItems":
                    case "maxItems":
                    case "minProperties":
                    case "maxProperties":
                        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var bound) || bound < 0)
                        {
                            throw new SchemaException($"{where}/{key}: must be a non-negative integer");
                        }
                        break;
                    case "minimum":
                    case "maximum":
                    case "exclusiveMinimum":
                    case "exclusiveMaximum":
                        if (value.ValueKind != JsonValueKind.Number)
                        {
                            throw new SchemaException($"{where}/{key}: must be a number");
                        }
                        EnsureExactNumbers(value, $"{where}/{key}");
                        break;
                    case "const":
                        EnsureExactNumbers(value, $"{where}/const");
                        break;
                    case "required":
                        if (value.ValueKind != JsonValueKind.Array || value.EnumerateArray().Any(name => name.ValueKind != JsonValueKind.String))
                        {
                            throw new SchemaException($"{where}/required: must be an array of property names");
                        }
                        break;
                    case "enum":
                        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() == 0)
                        {
                            throw new SchemaException($"{where}/enum: must be a non-empty array");
                        }
                        EnsureExactNumbers(value, $"{where}/enum");
                        break;
                    case "uniqueItems":
                        if (value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                        {
                            throw new SchemaException($"{where}/uniqueItems: must be a boolean");
                        }
                        break;
                    case "format":
                        if (value.ValueKind != JsonValueKind.String)
                        {
                            throw new SchemaException($"{where}/format: must be a string");
                        }
                        break;
                }
            }
        }

        /// <summary>
        /// Every number literal in a schema must be one this engine orders exactly — the same range
        /// the Python engine's Decimal holds while reading a file. Past it that engine refuses the
        /// token outright, so accepting it here would leave one manifest with two verdicts and
        /// CompareNumbers with nothing exact to say about the bound.
        /// </summary>
        private static void EnsureExactNumbers(JsonElement node, string where)
        {
            switch (node.ValueKind)
            {
                case JsonValueKind.Number when !TryNormalizeNumber(node.GetRawText(), out _, out _, out _):
                    throw new SchemaException(
                        $"{where}: the number {node.GetRawText()} is outside the exponent range this validator " +
                        "orders exactly, and no consumer of a manifest could hold it either");
                case JsonValueKind.Object:
                    foreach (var member in node.EnumerateObject())
                    {
                        EnsureExactNumbers(member.Value, $"{where}/{member.Name}");
                    }
                    break;
                case JsonValueKind.Array:
                    var position = 0;
                    foreach (var item in node.EnumerateArray())
                    {
                        EnsureExactNumbers(item, $"{where}/{position++}");
                    }
                    break;
            }
        }

        private static IEnumerable<string> TypeList(JsonElement type)
        {
            if (type.ValueKind == JsonValueKind.Array)
            {
                foreach (var item in type.EnumerateArray())
                {
                    yield return item.GetString() ?? "";
                }
            }
            else
            {
                yield return type.GetString() ?? "";
            }
        }

        private Regex Compile(JsonElement pattern, string where)
        {
            if (pattern.ValueKind != JsonValueKind.String)
            {
                throw new SchemaException($"{where}/pattern: must be a string");
            }
            var text = pattern.GetString()!;
            if (!_regexes.TryGetValue(text, out var regex))
            {
                // JSON Schema patterns are ECMA-262. .NET's ECMAScript mode and the Python engine's
                // portability check refuse the same non-portable constructs, so a pattern that
                // validates here validates identically in CI and in the editor.
                var unportable = NonPortableRegexConstructs.FirstOrDefault(text.Contains);
                if (unportable is not null)
                {
                    throw new SchemaException($"{where}/pattern: '{unportable}' is outside the portable (ECMA-262) regex subset in '{text}'");
                }
                var pythonOnly = PythonOnlyConstruct(text);
                if (pythonOnly is not null)
                {
                    throw new SchemaException($"{where}/pattern: {pythonOnly} in '{text}'");
                }
                var catastrophic = CatastrophicShape(text);
                if (catastrophic is not null)
                {
                    throw new SchemaException($"{where}/pattern: {catastrophic}, in '{text}'");
                }
                try
                {
                    regex = new Regex(text, RegexOptions.ECMAScript, RegexTimeout);
                }
                catch (ArgumentException ex)
                {
                    throw new SchemaException($"{where}/pattern: invalid regex '{text}': {ex.Message}");
                }
                _regexes[text] = regex;
            }
            return regex;
        }

        private JsonElement Resolve(JsonElement reference, string where)
        {
            var text = reference.ValueKind == JsonValueKind.String ? reference.GetString() : null;
            if (text is null || !text.StartsWith('#'))
            {
                throw new SchemaException($"{where}/$ref: only local '#/...' references are supported, got '{text}'");
            }
            // A $ref may only NAME a definition — '#', '#/$defs/<name>' or '#/definitions/<name>'
            // — and not descend past one. Every other target is refused because the walk never
            // reaches it: annotations other than $defs and definitions are skipped, so
            // `{"$ref": "#/default", "default": {...}}` validated against a subschema whose
            // keywords, patterns and numbers nothing had checked, and '#/$defs/a/default' reached
            // the same place one level lower. Refusing the shape closes both without walking
            // anything twice, and every shipped schema already writes #/$defs/<name>. The Python
            // twin refuses the same shapes.
            var segments = text.StartsWith("#/", StringComparison.Ordinal)
                ? text[2..].Split('/')
                : Array.Empty<string>();
            if (text != "#"
                && !(segments.Length == 2 && segments[1].Length > 0
                     && segments[0] is "$defs" or "definitions"))
            {
                throw new SchemaException(
                    $"{where}/$ref: '{text}' must be '#' or name one definition ('#/$defs/<name>' or " +
                    "'#/definitions/<name>'); nothing deeper is reached by the schema self-check");
            }
            var node = _root;
            var pointer = text[1..];
            if (pointer.Length == 0)
            {
                return node;
            }
            if (!pointer.StartsWith('/'))
            {
                throw new SchemaException($"{where}/$ref: unsupported reference '{text}'");
            }
            foreach (var rawToken in pointer[1..].Split('/'))
            {
                var token = rawToken.Replace("~1", "/").Replace("~0", "~");
                if (node.ValueKind == JsonValueKind.Object && node.TryGetProperty(token, out var child))
                {
                    node = child;
                }
                else if (node.ValueKind == JsonValueKind.Array
                         && int.TryParse(token, NumberStyles.None, CultureInfo.InvariantCulture, out var position)
                         && position < node.GetArrayLength())
                {
                    node = node[position];
                }
                else
                {
                    throw new SchemaException($"{where}/$ref: '{text}' does not resolve");
                }
            }
            return node;
        }

        // -- validation --------------------------------------------------------------

        public void Validate(JsonElement schema, JsonElement instance, string path, List<Issue> errors)
        {
            CountEvaluation(path);
            if (++_depth > MaxDepth)
            {
                _depth--;
                throw new SchemaException($"{path}: schema nesting deeper than {MaxDepth} levels — a $ref cycle that never descends into the instance");
            }
            try
            {
                ValidateCore(schema, instance, path, errors);
            }
            finally
            {
                _depth--;
            }
        }

        private void ValidateCore(JsonElement schema, JsonElement instance, string path, List<Issue> errors)
        {
            if (schema.ValueKind == JsonValueKind.True)
            {
                return;
            }
            if (schema.ValueKind == JsonValueKind.False)
            {
                errors.Add(new Issue(path, "False schema does not allow " + Brief(instance)));
                return;
            }

            if (schema.TryGetProperty("$ref", out var reference))
            {
                Validate(Resolve(reference, "#"), instance, path, errors);
            }

            if (schema.TryGetProperty("type", out var type))
            {
                var names = TypeList(type).ToList();
                if (!names.Any(name => MatchesType(instance, name)))
                {
                    var wanted = string.Join(", ", names.Select(name => $"'{name}'"));
                    errors.Add(new Issue(path, $"{Brief(instance)} is not of type {wanted}"));
                    return; // the remaining keywords are meaningless for the wrong type
                }
            }

            if (schema.TryGetProperty("enum", out var options) && !EnumContains(options, instance, path))
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is not one of {Display(options)}"));
            }
            if (schema.TryGetProperty("const", out var constant) && !JsonEquals(instance, constant))
            {
                errors.Add(new Issue(path, $"{Display(constant)} was expected"));
            }

            switch (instance.ValueKind)
            {
                case JsonValueKind.String:
                    ValidateString(schema, instance, path, errors);
                    break;
                case JsonValueKind.Number:
                    ValidateNumber(schema, instance, path, errors);
                    break;
                case JsonValueKind.Array:
                    ValidateArray(schema, instance, path, errors);
                    break;
                case JsonValueKind.Object:
                    ValidateObject(schema, instance, path, errors);
                    break;
            }

            if (schema.TryGetProperty("allOf", out var allOf))
            {
                foreach (var sub in allOf.EnumerateArray())
                {
                    Validate(sub, instance, path, errors);
                }
            }
            if (schema.TryGetProperty("anyOf", out var anyOf))
            {
                ValidateAlternatives(anyOf, instance, path, errors, exactlyOne: false);
            }
            if (schema.TryGetProperty("oneOf", out var oneOf))
            {
                ValidateAlternatives(oneOf, instance, path, errors, exactlyOne: true);
            }
            if (schema.TryGetProperty("not", out var not) && ErrorsFor(not, instance, path).Count == 0)
            {
                errors.Add(new Issue(path, $"{Brief(instance)} should not be valid under {Brief(not)}"));
            }
            if (schema.TryGetProperty("if", out var condition))
            {
                var branch = ErrorsFor(condition, instance, path).Count == 0 ? "then" : "else";
                if (schema.TryGetProperty(branch, out var branchSchema))
                {
                    Validate(branchSchema, instance, path, errors);
                }
            }
        }

        private List<Issue> ErrorsFor(JsonElement schema, JsonElement instance, string path)
        {
            var collected = new List<Issue>();
            Validate(schema, instance, path, collected);
            return collected;
        }

        private void ValidateAlternatives(
            JsonElement options, JsonElement instance, string path, List<Issue> errors, bool exactlyOne)
        {
            var branches = options.EnumerateArray().ToList();
            var outcomes = branches.Select(option => ErrorsFor(option, instance, path)).ToList();
            var matches = outcomes.Count(outcome => outcome.Count == 0);
            if (matches == 0)
            {
                // Report the closest branch: fewest errors, preferring one whose declared
                // type matches the instance so an object is judged as an object.
                var best = Enumerable.Range(0, branches.Count)
                    .OrderBy(index => DeclaredTypeMatches(branches[index], instance) ? 0 : 1)
                    .ThenBy(index => outcomes[index].Count)
                    .First();
                var keyword = exactlyOne ? "oneOf" : "anyOf";
                errors.Add(new Issue(path, $"{Brief(instance)} is not valid under any of the given schemas ({keyword})"));
                errors.AddRange(outcomes[best]);
            }
            else if (exactlyOne && matches > 1)
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is valid under each of {matches} oneOf schemas"));
            }
        }

        private bool DeclaredTypeMatches(JsonElement option, JsonElement instance)
        {
            if (option.ValueKind != JsonValueKind.Object)
            {
                return false;
            }
            if (!option.TryGetProperty("type", out var declared) && option.TryGetProperty("$ref", out var reference))
            {
                var resolved = Resolve(reference, "#");
                if (resolved.ValueKind != JsonValueKind.Object || !resolved.TryGetProperty("type", out declared))
                {
                    return false;
                }
            }
            return declared.ValueKind != JsonValueKind.Undefined
                   && TypeList(declared).Any(name => MatchesType(instance, name));
        }

        private void ValidateString(JsonElement schema, JsonElement instance, string path, List<Issue> errors)
        {
            var value = instance.GetString() ?? "";
            var length = value.EnumerateRunes().Count(); // Unicode code points, as the spec and the Python engine count
            if (schema.TryGetProperty("minLength", out var minLength) && length < minLength.GetInt32())
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is too short (minLength {minLength.GetInt32()})"));
            }
            if (schema.TryGetProperty("maxLength", out var maxLength) && length > maxLength.GetInt32())
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is too long (maxLength {maxLength.GetInt32()})"));
            }
            if (schema.TryGetProperty("pattern", out var pattern) && !Matches(Compile(pattern, path), value, path))
            {
                errors.Add(new Issue(path, $"{Brief(instance)} does not match {Display(pattern)}"));
            }
            if (schema.TryGetProperty("format", out var format) && format.ValueKind == JsonValueKind.String)
            {
                var name = format.GetString()!;
                var ok = name switch
                {
                    "date" => IsDate(value),
                    "date-time" => IsDateTime(value),
                    _ => true, // unknown formats are annotations per the spec
                };
                if (!ok)
                {
                    errors.Add(new Issue(path, $"{Brief(instance)} is not a {Display(format)}"));
                }
            }
        }

        private static bool IsDate(string value) =>
            value.Length == 10
            && DateOnly.TryParseExact(value, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out _);

        // RFC 3339 shape first (DateTimeOffset.TryParse is lenient: it takes surrounding
        // whitespace and many non-ISO spellings), then a real calendar/clock check.
        // Date, 'T', hh:mm:ss (fraction optional) and a MANDATORY offset (Z or +-hh:mm): what
        // jsonschema + rfc3339-validator and the Python engine accept, nothing more.
        private static readonly Regex DateTimeShape = new(
            @"^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})$",
            RegexOptions.ECMAScript, RegexTimeout);

        // Two catastrophic shapes, found by walking the pattern rather than by matching it
        // with another regex (a regex cannot skip character classes or count alternatives
        // reliably): a group whose whole content is ONE quantified atom, quantified again
        // (^(a+)+$, (\d*)*, ([a-z]+){2,}, (x{2,})+, (a+?)+), and a group carrying a top-level
        // alternation, quantified (^(a|aa)+$, (?:ab|a)*, (a|aa|aaa)+). Both backtrack
        // exponentially; refused before the regex is built, with a message that names the mistake.
        // This scan is NOT the safety guarantee - it only knows the shapes it enumerates, and
        // ^(a+a+)+$ is not one of them. The guarantee is RegexTimeout: every match this engine runs
        // is bounded by it whatever the pattern looks like (Matches below turns a timeout into a
        // verdict, as _bounded does in the Python twin). A group that must consume a literal each iteration - ([a-z]+/)*,
        // (?:ab*)*c - is linear; a bounded quantifier - (a|b)? - is safe; and a '(' or '|' inside
        // a character class - [(a|b)+] - is a literal, not structure. The twin of
        // _catastrophic_shape in scripts/validation/validate_config_schemas.py.
        private static (int Length, bool Multiplying) QuantifierAt(string pattern, int index)
        {
            if (index >= pattern.Length)
            {
                return (0, false);
            }
            var c = pattern[index];
            if (c is '+' or '*')
            {
                return (1, true);
            }
            if (c == '?')
            {
                return (1, false);
            }
            if (c != '{')
            {
                return (0, false);
            }
            // Scan forward to the first character that cannot be part of a repetition count,
            // rather than searching the rest of the pattern for '}': IndexOf is O(n) per '{',
            // which made this preflight quadratic on a pattern of unmatched braces. Each character
            // is consumed by at most one scan, so the walk stays linear however the braces are
            // arranged — and a body of leading zeros is still read as the count it is. The Python
            // twin scans the same way.
            var cursor = index + 1;
            while (cursor < pattern.Length && (char.IsAsciiDigit(pattern[cursor]) || pattern[cursor] == ','))
            {
                cursor++;
            }
            if (cursor >= pattern.Length || pattern[cursor] != '}')
            {
                return (0, false);
            }
            var close = cursor;
            var body = pattern[(index + 1)..close];
            var comma = body.IndexOf(',');
            var low = comma < 0 ? body : body[..comma];
            var high = comma < 0 ? null : body[(comma + 1)..];
            if (!IsCount(low) || (high is { Length: > 0 } && !IsCount(high)))
            {
                return (0, false); // not a quantifier, just a literal brace
            }
            if (comma < 0)
            {
                return (close - index + 1, CountValue(low) > 1);
            }
            return (close - index + 1, high!.Length == 0 || CountValue(high) > 1);
        }

        /// <summary>
        /// This parser refuses a repetition count above Int32.MaxValue outright ("Quantifier and
        /// capture group numbers must be less than or equal to Int32.MaxValue") while Python
        /// compiles it, so a pattern carrying one is usable in CI and unusable here.
        /// </summary>
        private const long MaxRepetition = 2_147_483_647;

        /// <summary>
        /// `{,n}` or `{,}` at <paramref name="index"/>: Python reads them as {0,n} and {0,}; this
        /// parser reads literal characters. So `^a{,3}$` matches "aa" in one engine and only the
        /// text "a{,3}" in the other — and `a{,3}+` is a possessive quantifier QuantifierAt, which
        /// needs a lower bound, never sees.
        /// </summary>
        private static bool OmittedLowerBound(string pattern, int index)
        {
            var cursor = index + 1;
            if (cursor >= pattern.Length || pattern[cursor] != ',')
            {
                return false;
            }
            cursor++;
            while (cursor < pattern.Length && char.IsAsciiDigit(pattern[cursor]))
            {
                cursor++;
            }
            return cursor < pattern.Length && pattern[cursor] == '}';
        }

        /// <summary>A `{n}` / `{n,}` / `{n,m}` whose count is past what this parser accepts.</summary>
        private static bool OversizedCount(string pattern, int index)
        {
            var cursor = index + 1;
            while (cursor < pattern.Length && (char.IsAsciiDigit(pattern[cursor]) || pattern[cursor] == ','))
            {
                cursor++;
            }
            if (cursor >= pattern.Length || pattern[cursor] != '}')
            {
                return false;
            }
            var body = pattern[(index + 1)..cursor];
            var comma = body.IndexOf(',');
            var low = comma < 0 ? body : body[..comma];
            var high = comma < 0 ? null : body[(comma + 1)..];
            return (IsCount(low) && CountAbove(low)) || (high is { Length: > 0 } && IsCount(high) && CountAbove(high));
        }

        /// <summary>The count spelled by <paramref name="text"/> exceeds MaxRepetition.</summary>
        private static bool CountAbove(string text)
        {
            var stripped = text.TrimStart('0');
            if (stripped.Length == 0)
            {
                return false;
            }
            return stripped.Length > 10
                   || !long.TryParse(stripped, NumberStyles.None, CultureInfo.InvariantCulture, out var value)
                   || value > MaxRepetition;
        }

        private static bool IsCount(string text) => text.Length > 0 && text.All(char.IsAsciiDigit);

        /// <summary>
        /// A repetition count, or 2 when it is longer than any engine could hold: such a count
        /// multiplies anyway, and parsing it would overflow. Leading zeros are stripped first, so
        /// {0000000000000000000000000000000000000002} is the count two, however it is spelled.
        /// </summary>
        private static long CountValue(string text)
        {
            var stripped = text.TrimStart('0');
            if (stripped.Length == 0)
            {
                return 0;
            }
            return stripped.Length <= 18 && long.TryParse(stripped, NumberStyles.None, CultureInfo.InvariantCulture, out var value)
                ? value
                : 2;
        }

        private sealed class GroupFrame
        {
            public bool Alternation;
            public int Atoms;
            public int Quantifiers;
        }

        internal static string? CatastrophicShape(string pattern)
        {
            var frames = new Stack<GroupFrame>();
            var current = new GroupFrame();
            var index = 0;
            while (index < pattern.Length)
            {
                var c = pattern[index];
                if (c == '\\')
                {
                    index += 2;
                    current.Atoms++;
                    continue;
                }
                if (c == '[')
                {
                    var cursor = index + 1;
                    if (cursor < pattern.Length && pattern[cursor] == '^')
                    {
                        cursor++;
                    }
                    if (cursor < pattern.Length && pattern[cursor] == ']')
                    {
                        cursor++; // a leading ']' is a literal
                    }
                    while (cursor < pattern.Length && pattern[cursor] != ']')
                    {
                        cursor += pattern[cursor] == '\\' ? 2 : 1;
                    }
                    index = cursor + 1;
                    current.Atoms++;
                    continue;
                }
                if (c == '(')
                {
                    frames.Push(current);
                    current = new GroupFrame();
                    index++;
                    if (index + 1 < pattern.Length && pattern[index] == '?' && pattern[index + 1] == ':')
                    {
                        index += 2;
                    }
                    else if (index < pattern.Length && pattern[index] == '?')
                    {
                        index++;
                        while (index < pattern.Length && pattern[index] is '=' or '!' or '<')
                        {
                            index++;
                        }
                    }
                    continue;
                }
                if (c == ')')
                {
                    var inner = current;
                    current = frames.Count > 0 ? frames.Pop() : new GroupFrame();
                    index++;
                    var (size, multiplying) = QuantifierAt(pattern, index);
                    if (size > 0)
                    {
                        index += size;
                        if (index < pattern.Length && pattern[index] == '?')
                        {
                            index++; // lazy marker
                        }
                        if (multiplying)
                        {
                            if (inner.Alternation)
                            {
                                return "a quantified group carries an alternation (ambiguous backtracking); write a character class or split the pattern";
                            }
                            if (inner.Atoms == 1 && inner.Quantifiers == 1)
                            {
                                return "a quantified group is itself quantified (catastrophic backtracking)";
                            }
                        }
                        current.Quantifiers++;
                    }
                    current.Atoms++;
                    continue;
                }
                if (c == '|')
                {
                    current.Alternation = true;
                    current.Atoms = 0; // each alternative is measured on its own
                    current.Quantifiers = 0;
                    index++;
                    continue;
                }
                if (c is '^' or '$')
                {
                    index++; // an anchor is not an atom
                    continue;
                }
                var (atomQuantifier, _) = QuantifierAt(pattern, index);
                if (atomQuantifier > 0 && current.Atoms > 0)
                {
                    index += atomQuantifier;
                    if (index < pattern.Length && pattern[index] == '?')
                    {
                        index++;
                    }
                    current.Quantifiers++;
                    continue;
                }
                index++;
                current.Atoms++;
            }
            return null;
        }

        /// <summary>
        /// One match under the compiled pattern's Regex timeout. A pattern that backtracks is the
        /// schema's problem and is reported as one, never as an exception out of the MCP tool; the
        /// Python twin's _bounded says the same thing through SIGALRM.
        /// </summary>
        private static bool Matches(Regex regex, string value, string where)
        {
            try
            {
                return regex.IsMatch(value);
            }
            catch (RegexMatchTimeoutException)
            {
                throw new SchemaException(
                    $"{where}/pattern: matching '{regex}' did not finish within {RegexTimeout.TotalSeconds:0.#}s and was abandoned; " +
                    "the pattern backtracks on this input - rewrite it (a character class, or a literal that must be " +
                    "consumed each repetition, instead of a quantified group)");
            }
        }

        private static bool IsDateTime(string value)
        {
            // Shape first, then a real calendar and clock check — but NOT through DateTimeOffset,
            // which cannot hold an offset beyond ±14:00 while RFC 3339 (and the Python twin, whose
            // fromisoformat accepts ±23:59) allows any two-digit hour. The regex has already fixed
            // every field's position, so the parts can be read directly.
            // '$' in .NET matches before a final newline, so the shape alone would accept
            // "2026-01-01T00:00:00Z\n" and then read its offset from the wrong six characters.
            if (value.Length == 0 || value[^1] is '\n' or '\r' || !DateTimeShape.IsMatch(value))
            {
                return false;
            }
            var local = string.Concat(value[..10], "T", value[11..19]);
            if (!DateTime.TryParseExact(local, "yyyy-MM-ddTHH:mm:ss", CultureInfo.InvariantCulture,
                    DateTimeStyles.None, out _))
            {
                return false;
            }
            var offset = value[^6..];
            if (offset[0] is not ('+' or '-'))
            {
                return true;   // the shape guarantees the only other ending is Z or z
            }
            return int.TryParse(offset[1..3], NumberStyles.None, CultureInfo.InvariantCulture, out var hours)
                && int.TryParse(offset[4..6], NumberStyles.None, CultureInfo.InvariantCulture, out var minutes)
                && hours <= 23 && minutes <= 59;
        }

        // Constructs .NET, Python and ECMA-262 do not share; refused by name so both engines agree.
        private static readonly string[] NonPortableRegexConstructs =
        {
            "\\A", "\\Z", "\\z", "\\G", "(?<=", "(?<!", "\\p{", "\\P{", "(?i)", "(?m)", "(?s)", "(?x)", "(?#",
        };

        /// <summary>
        /// The reason a pattern uses a construct Python has and ECMA-262 does not, or null. Python
        /// 3.11 accepts possessive quantifiers (a++, a*+, a?+, a{2,3}+) and atomic groups ((?>...));
        /// this parser reads the second '+' as a nested quantifier and refuses the pattern, so
        /// without the refusal a schema using one passes CI and is unusable here. Naming the
        /// construct is the point: both engines refuse it for the same stated reason. Found by
        /// walking the pattern rather than by searching for a substring, so a literal '\\++' and a
        /// character class '[(?>]' are read as what they are and stay legal. The twin of
        /// _python_only_construct in scripts/validation/validate_config_schemas.py.
        /// </summary>
        internal static string? PythonOnlyConstruct(string pattern)
        {
            var index = 0;
            while (index < pattern.Length)
            {
                var c = pattern[index];
                if (c == '\\')
                {
                    index += 2;
                    continue;
                }
                if (c == '[')
                {
                    var cursor = index + 1;
                    if (cursor < pattern.Length && pattern[cursor] == '^')
                    {
                        cursor++;
                    }
                    if (cursor < pattern.Length && pattern[cursor] == ']')
                    {
                        cursor++; // a leading ']' is a literal
                    }
                    while (cursor < pattern.Length && pattern[cursor] != ']')
                    {
                        cursor += pattern[cursor] == '\\' ? 2 : 1;
                    }
                    index = cursor + 1;
                    continue;
                }
                if (c == '(' && pattern.AsSpan(index + 1).StartsWith("?>"))
                {
                    return "an atomic group ('(?>') is outside the portable (ECMA-262) regex subset";
                }
                if (c == '{' && OmittedLowerBound(pattern, index))
                {
                    return "an omitted lower bound ('{,n}') is outside the portable (ECMA-262) regex subset";
                }
                if (c == '{' && OversizedCount(pattern, index))
                {
                    return $"a repetition count above {MaxRepetition} is outside the range every engine holds";
                }
                var (length, _) = QuantifierAt(pattern, index);
                if (length > 0)
                {
                    index += length;
                    if (index < pattern.Length && pattern[index] == '+')
                    {
                        return "a possessive quantifier ('++', '*+', '?+', '{n,m}+') is outside the portable (ECMA-262) regex subset";
                    }
                    if (index < pattern.Length && pattern[index] == '?')
                    {
                        index++;   // lazy: legal in both dialects
                    }
                    continue;
                }
                index++;
            }
            return null;
        }

        private static void ValidateNumber(JsonElement schema, JsonElement instance, string path, List<Issue> errors)
        {
            // The Python engine refuses a token outside double range while parsing ("1e400" reads
            // as inf, and System.Text.Json's binders fail on it), and refuses an exponent its own
            // Decimal cannot hold; JsonDocument parses both happily, so the same manifest would be
            // valid here and unreadable there. Say so once, before any bound is compared — which is
            // also what leaves CompareNumbers with two numbers it can order exactly.
            if (!IsFiniteNumber(instance))
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is out of range for a JSON number: no consumer of this manifest can hold it"));
                return;
            }
            // Compared as written, not as doubles: minimum 9007199254740993 against the integer
            // 9007199254740992 is the same double twice, and the invalid instance would pass.
            if (schema.TryGetProperty("minimum", out var minimum) && CompareNumbers(instance, minimum) < 0)
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is less than the minimum of {Display(minimum)}"));
            }
            if (schema.TryGetProperty("maximum", out var maximum) && CompareNumbers(instance, maximum) > 0)
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is greater than the maximum of {Display(maximum)}"));
            }
            if (schema.TryGetProperty("exclusiveMinimum", out var exclusiveMinimum) && CompareNumbers(instance, exclusiveMinimum) <= 0)
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is less than or equal to the minimum of {Display(exclusiveMinimum)}"));
            }
            if (schema.TryGetProperty("exclusiveMaximum", out var exclusiveMaximum) && CompareNumbers(instance, exclusiveMaximum) >= 0)
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is greater than or equal to the maximum of {Display(exclusiveMaximum)}"));
            }
        }

        private void ValidateArray(JsonElement schema, JsonElement instance, string path, List<Issue> errors)
        {
            var items = instance.EnumerateArray().ToList();
            if (schema.TryGetProperty("minItems", out var minItems) && items.Count < minItems.GetInt32())
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is too short (minItems {minItems.GetInt32()})"));
            }
            if (schema.TryGetProperty("maxItems", out var maxItems) && items.Count > maxItems.GetInt32())
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is too long (maxItems {maxItems.GetInt32()})"));
            }
            if (schema.TryGetProperty("uniqueItems", out var unique) && unique.ValueKind == JsonValueKind.True)
            {
                var seen = new HashSet<string>(StringComparer.Ordinal);
                for (var index = 0; index < items.Count; index++)
                {
                    if (!seen.Add(Canonical(items[index])))
                    {
                        errors.Add(new Issue($"{path}[{index}]", $"{Brief(instance)} has non-unique elements"));
                        break;
                    }
                }
            }
            if (schema.TryGetProperty("items", out var itemSchema))
            {
                for (var index = 0; index < items.Count; index++)
                {
                    Validate(itemSchema, items[index], $"{path}[{index}]", errors);
                }
            }
            if (schema.TryGetProperty("contains", out var contains)
                && !items.Select((item, index) => ErrorsFor(contains, item, $"{path}[{index}]").Count == 0).Any(ok => ok))
            {
                errors.Add(new Issue(path, $"{Brief(instance)} does not contain items matching the given schema"));
            }
        }

        private void ValidateObject(JsonElement schema, JsonElement instance, string path, List<Issue> errors)
        {
            var members = instance.EnumerateObject().ToList();
            if (schema.TryGetProperty("required", out var required))
            {
                foreach (var name in required.EnumerateArray())
                {
                    var wanted = name.GetString() ?? "";
                    if (!instance.TryGetProperty(wanted, out _))
                    {
                        errors.Add(new Issue(path, $"'{wanted}' is a required property"));
                    }
                }
            }
            if (schema.TryGetProperty("minProperties", out var minProperties) && members.Count < minProperties.GetInt32())
            {
                errors.Add(new Issue(path, $"{Brief(instance)} does not have enough properties (minProperties {minProperties.GetInt32()})"));
            }
            if (schema.TryGetProperty("maxProperties", out var maxProperties) && members.Count > maxProperties.GetInt32())
            {
                errors.Add(new Issue(path, $"{Brief(instance)} has too many properties (maxProperties {maxProperties.GetInt32()})"));
            }

            schema.TryGetProperty("properties", out var properties);
            schema.TryGetProperty("patternProperties", out var patternProperties);
            // Compiled once per schema, not once per (pattern, member) pair: the old shape parsed a
            // JsonDocument for every attempt, and P patterns against N keys is P×N of them.
            var compiledPatterns = new List<(string Pattern, Regex Regex)>();
            if (patternProperties.ValueKind == JsonValueKind.Object)
            {
                foreach (var candidate in patternProperties.EnumerateObject())
                {
                    using var patternDocument = JsonDocument.Parse($"\"{JsonEncodedText.Encode(candidate.Name)}\"");
                    compiledPatterns.Add((candidate.Name, Compile(patternDocument.RootElement.Clone(), path)));
                }
            }
            var hasAdditional = schema.TryGetProperty("additionalProperties", out var additional);
            var hasPropertyNames = schema.TryGetProperty("propertyNames", out var propertyNames);
            var unexpected = new List<string>();

            foreach (var member in members)
            {
                var child = $"{path}.{member.Name}";
                var matched = false;
                if (properties.ValueKind == JsonValueKind.Object && properties.TryGetProperty(member.Name, out var propertySchema))
                {
                    matched = true;
                    Validate(propertySchema, member.Value, child, errors);
                }
                foreach (var (pattern, regex) in compiledPatterns)
                {
                    // Every attempt is charged: P patterns against N keys is P×N matches, and only
                    // recursive Validate calls used to touch the budget, so a pair of large files
                    // could spend millions of matches against one instance evaluation.
                    CountEvaluation(path);
                    if (Matches(regex, member.Name, path))
                    {
                        matched = true;
                        Validate(patternProperties.GetProperty(pattern), member.Value, child, errors);
                    }
                }
                if (!matched && hasAdditional)
                {
                    if (additional.ValueKind == JsonValueKind.False)
                    {
                        unexpected.Add(member.Name);
                    }
                    else
                    {
                        Validate(additional, member.Value, child, errors);
                    }
                }
                if (hasPropertyNames)
                {
                    // Reported at the object, not at the key's own path: that is where
                    // python-jsonschema and the Python twin report a bad property name.
                    using var nameDocument = JsonDocument.Parse($"\"{JsonEncodedText.Encode(member.Name)}\"");
                    Validate(propertyNames, nameDocument.RootElement.Clone(), path, errors);
                }
            }

            if (unexpected.Count > 0)
            {
                var listed = string.Join(", ", unexpected.Select(name => $"'{name}'"));
                var verb = unexpected.Count > 1 ? "were" : "was";
                errors.Add(new Issue(path, $"Additional properties are not allowed ({listed} {verb} unexpected)"));
            }
        }

        // -- helpers -----------------------------------------------------------------

        private static bool IsInteger(JsonElement number)
        {
            if (number.TryGetInt64(out _))
            {
                return true;
            }
            // As written, not as a double: 1e-324 and 1.00000000000000001 round to 0 and 1 there,
            // and the Python twin - whose numbers are exact - calls neither an integer.
            if (TryNormalizeNumber(number.GetRawText(), out _, out var significant, out var exponent))
            {
                return significant.Length == 0 || exponent >= 0;
            }
            // Only an exponent past the normalizer's guard reaches here, and a double would answer
            // for a value it cannot hold: 1e-1000000001 becomes zero and would read as an integer,
            // where the Python engine - whose numbers are exact - calls it fractional.
            return false;
        }

        private static bool MatchesType(JsonElement instance, string expected) => expected switch
        {
            "null" => instance.ValueKind == JsonValueKind.Null,
            "boolean" => instance.ValueKind is JsonValueKind.True or JsonValueKind.False,
            "object" => instance.ValueKind == JsonValueKind.Object,
            "array" => instance.ValueKind == JsonValueKind.Array,
            "string" => instance.ValueKind == JsonValueKind.String,
            "number" => instance.ValueKind == JsonValueKind.Number,
            "integer" => instance.ValueKind == JsonValueKind.Number && IsInteger(instance),
            _ => false,
        };

        /// <summary>
        /// <paramref name="instance"/> is one of <paramref name="options"/>, charging every
        /// comparison and rendering the instance once. Nothing used to charge here, and JsonEquals
        /// re-rendered the whole instance per option: a 200,000-entry enum against a 100 KB string
        /// drove billions of characters of rendering for a single keyword evaluation, and this
        /// engine has no whole-request deadline. Both keys are computed on first use and reused, so
        /// the cost of the keyword is bounded by the size of the two documents. The Python twin
        /// (_enum_contains) caches the same two keys.
        /// </summary>
        private bool EnumContains(JsonElement options, JsonElement instance, string path)
        {
            if (options.ValueKind != JsonValueKind.Array)
            {
                return false;
            }
            var keys = new InstanceKeys(instance);
            foreach (var option in options.EnumerateArray())
            {
                CountEvaluation(path);
                if (JsonEquals(keys, option))
                {
                    return true;
                }
            }
            return false;
        }

        /// <summary>The equality keys for one instance, each rendered at most once.</summary>
        private sealed class InstanceKeys
        {
            private string? _number;
            private string? _canonical;

            public InstanceKeys(JsonElement value) => Value = value;

            public JsonElement Value { get; }

            public string Number => _number ??= CanonicalNumber(Value);

            public string CanonicalKey => _canonical ??= Canonical(Value);
        }

        private static bool JsonEquals(JsonElement left, JsonElement right) =>
            JsonEquals(new InstanceKeys(left), right);

        private static bool JsonEquals(InstanceKeys left, JsonElement right)
        {
            if (left.Value.ValueKind == JsonValueKind.Number && right.ValueKind == JsonValueKind.Number)
            {
                // As written, not as doubles: 9007199254740992 and 9007199254740993 share one
                // double. See CanonicalNumber.
                return left.Number == CanonicalNumber(right);
            }
            if (left.Value.ValueKind is JsonValueKind.True or JsonValueKind.False
                || right.ValueKind is JsonValueKind.True or JsonValueKind.False)
            {
                return left.Value.ValueKind == right.ValueKind;
            }
            return left.CanonicalKey == Canonical(right);
        }

        /// <summary>Canonical form for messages: a whole manifest quoted back is noise, not a hint.</summary>
        private static string Brief(JsonElement element)
        {
            const int limit = 120;
            var text = Display(element);
            return text.Length <= limit ? text : text[..(limit - 3)] + "...";
        }

        /// <summary>Compact JSON, object keys sorted: the equality key, with numbers normalized exactly.</summary>
        private static string Canonical(JsonElement element) => Render(element, exactNumbers: true);

        /// <summary>The same shape for a message, where a number reads back as the manifest wrote it.</summary>
        private static string Display(JsonElement element) => Render(element, exactNumbers: false);

        private static string Render(JsonElement element, bool exactNumbers)
        {
            switch (element.ValueKind)
            {
                case JsonValueKind.Object:
                    var members = element.EnumerateObject()
                        .OrderBy(member => member.Name, StringComparer.Ordinal)
                        .Select(member => JsonSerializer.Serialize(member.Name) + ":" + Render(member.Value, exactNumbers));
                    return "{" + string.Join(",", members) + "}";
                case JsonValueKind.Array:
                    return "[" + string.Join(",", element.EnumerateArray().Select(item => Render(item, exactNumbers))) + "]";
                case JsonValueKind.String:
                    // Compare the VALUE, not the source text: "\u0041" and "A" are the same string.
                    return JsonSerializer.Serialize(element.GetString());
                case JsonValueKind.Number:
                    return exactNumbers ? CanonicalNumber(element) : element.GetRawText();
                default:
                    return element.GetRawText();
            }
        }

        /// <summary>
        /// Canonical text for a JSON number, exact for every token JSON can spell. 1, 1.0 and 1e0 are
        /// one number and must share this text; 9007199254740992 and 9007199254740993 are two, and so
        /// are 0 and 1e-29 - which is why neither double (it rounds the first pair together) nor
        /// decimal (it rounds 1e-29 to zero) can produce it. The token is normalized arithmetically
        /// instead: sign, the significant digits with leading and trailing zeros removed, and the
        /// power of ten that scales them. Python's json keeps integers exact and compares numbers
        /// numerically, so this is also what keeps the two engines agreeing about one manifest.
        /// </summary>
        internal static string CanonicalNumberFor(JsonElement element) => CanonicalNumber(element);

        private static string CanonicalNumber(JsonElement element)
        {
            var raw = element.GetRawText();
            if (!TryNormalizeNumber(raw, out var negative, out var significant, out var exponent))
            {
                return raw; // an exponent no long holds: the token as written is its own key
            }
            return significant.Length == 0
                ? "0"
                : (negative ? "-" : "") + significant + "e" + exponent.ToString(CultureInfo.InvariantCulture);
        }

        internal static bool TryGetWholeNumberFor(JsonElement number, out long value)
        {
            value = 0;
            if (number.ValueKind != JsonValueKind.Number
                || !TryNormalizeNumber(number.GetRawText(), out var negative, out var digits, out var exponent))
            {
                return false;
            }
            if (digits.Length == 0)
            {
                return true;   // zero, however it is spelled
            }
            // Fractional, or too wide for any long. Within 19 digits the whole number is spelled
            // out and long.TryParse decides — so long.MaxValue and long.MinValue both read exactly,
            // where an 18-digit ceiling refused them.
            if (exponent < 0 || digits.Length + exponent > 19)
            {
                return false;
            }
            var whole = exponent == 0 ? digits : digits + new string('0', (int)exponent);
            return long.TryParse(negative ? "-" + whole : whole, NumberStyles.AllowLeadingSign,
                                 CultureInfo.InvariantCulture, out value);
        }

        /// <summary>True when this token's exponent is inside the range ordered exactly here.</summary>
        internal static bool IsExactNumber(JsonElement number) =>
            TryNormalizeNumber(number.GetRawText(), out _, out _, out _);

        /// <summary>Splits a JSON number token into sign, significant digits and a power of ten.</summary>
        private static bool TryNormalizeNumber(string raw, out bool negative, out string significant, out long exponent)
        {
            negative = raw.StartsWith('-');
            significant = "";
            exponent = 0;
            var body = negative ? raw[1..] : raw;
            var exponentAt = body.IndexOfAny(new[] { 'e', 'E' });
            if (exponentAt >= 0)
            {
                // The bound keeps the arithmetic below from wrapping: subtracting a fraction's
                // digits from long.MinValue would turn a tiny number into an enormous one and
                // reverse the comparison. It sits where the Python engine's own numbers stop —
                // decimal.Decimal refuses a larger exponent while READING the file — so every token
                // that engine can hold is ordered exactly here instead of through a double, which
                // is what made `minimum: 1e-1000000001` and the instance 0 two zeroes.
                //
                // It is applied to the exponent AS WRITTEN, before the adjustments below, because
                // that literal is the one thing both engines can read without reproducing the
                // other's arithmetic: judging a normalized exponent instead put
                // 1.1e-999999999999999999 and 10e-1000000000000000000 — one scaled up by its
                // fraction, one down by its trailing zero — on opposite sides in the two engines.
                // Zero is judged the same way for the same reason. The adjustments then move the
                // exponent by at most the token's length, which leaves this three orders of
                // magnitude clear of long.MinValue.
                const long exponentLimit = 999_999_999_999_999_999;
                // Compared, not Math.Abs'd: Math.Abs(long.MinValue) throws, and long.MinValue is
                // exactly the exponent an attacker would write.
                if (!long.TryParse(body[(exponentAt + 1)..], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out exponent)
                    || exponent > exponentLimit || exponent < -exponentLimit)
                {
                    return false;
                }
                // Zero is zero however it is spelled: 0e-1000000001 has nothing for an exponent to
                // scale, so it normalizes to "0" once the written exponent is in range.
                if (body[..exponentAt].Trim('0').Trim('.').Length == 0)
                {
                    exponent = 0;
                    return true;
                }
                body = body[..exponentAt];
            }
            var point = body.IndexOf('.');
            if (point >= 0)
            {
                exponent -= body.Length - point - 1;
                body = string.Concat(body[..point], body[(point + 1)..]);
            }
            var digits = body.TrimStart('0');
            significant = digits.TrimEnd('0');
            exponent += digits.Length - significant.Length;
            return true;
        }

        /// <summary>
        /// Orders two JSON numbers by value, exactly. Magnitudes are compared by the power of ten
        /// of their leading digit and then digit by digit, so nothing is scaled into a big integer
        /// a hostile exponent could blow up, and nothing rounds through a double on the way.
        /// </summary>
        private static int CompareNumbers(JsonElement left, JsonElement right)
        {
            if (!TryNormalizeNumber(left.GetRawText(), out var leftNegative, out var leftDigits, out var leftExponent)
                || !TryNormalizeNumber(right.GetRawText(), out var rightNegative, out var rightDigits, out var rightExponent))
            {
                // Unreachable for a document either engine accepts: ValidateNumber refuses an
                // instance number outside double range before any bound is compared, and CheckSchema
                // refuses a schema number past the exponent limit wherever the walk reaches — which,
                // since the walk follows $ref, is everywhere a bound can be. Comparing doubles here
                // is what made 1e-1000000001 equal to zero, so there is no such fallback any more.
                throw new SchemaException(
                    "a number token beyond this validator's exponent range cannot be ordered exactly: " +
                    $"'{left.GetRawText()}' against '{right.GetRawText()}'");
            }
            var leftZero = leftDigits.Length == 0;
            var rightZero = rightDigits.Length == 0;
            if (leftZero || rightZero)
            {
                return leftZero && rightZero ? 0 : leftZero ? (rightNegative ? 1 : -1) : (leftNegative ? -1 : 1);
            }
            if (leftNegative != rightNegative)
            {
                return leftNegative ? -1 : 1;
            }
            var magnitude = CompareMagnitude(leftDigits, leftExponent, rightDigits, rightExponent);
            return leftNegative ? -magnitude : magnitude;
        }

        private static int CompareMagnitude(string leftDigits, long leftExponent, string rightDigits, long rightExponent)
        {
            // The power of ten of the leading digit: 1e2 (digits "1", exponent 2) is 100.
            var leftScale = leftExponent + leftDigits.Length;
            var rightScale = rightExponent + rightDigits.Length;
            if (leftScale != rightScale)
            {
                return leftScale < rightScale ? -1 : 1;
            }
            var width = Math.Max(leftDigits.Length, rightDigits.Length);
            for (var index = 0; index < width; index++)
            {
                var leftDigit = index < leftDigits.Length ? leftDigits[index] : '0';
                var rightDigit = index < rightDigits.Length ? rightDigits[index] : '0';
                if (leftDigit != rightDigit)
                {
                    return leftDigit < rightDigit ? -1 : 1;
                }
            }
            return 0;
        }

    }
}
