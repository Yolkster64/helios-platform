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
        var issues = new List<Issue>();
        validator.Validate(schemaRoot, instance, "$", issues);
        return issues;
    }

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

        public Validator(JsonElement root)
        {
            _root = root;
        }

        // -- schema self-check -------------------------------------------------------

        public void CheckSchema() => WalkSchema(_root, "#");

        private void WalkSchema(JsonElement node, string where)
        {
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
                if (NestedQuantifier.IsMatch(text))
                {
                    throw new SchemaException($"{where}/pattern: a quantified group is itself quantified (catastrophic backtracking) in '{text}'");
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

            if (schema.TryGetProperty("enum", out var options)
                && !options.EnumerateArray().Any(option => JsonEquals(instance, option)))
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is not one of {Canonical(options)}"));
            }
            if (schema.TryGetProperty("const", out var constant) && !JsonEquals(instance, constant))
            {
                errors.Add(new Issue(path, $"{Canonical(constant)} was expected"));
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
            if (schema.TryGetProperty("pattern", out var pattern) && !Compile(pattern, path).IsMatch(value))
            {
                errors.Add(new Issue(path, $"{Brief(instance)} does not match {Canonical(pattern)}"));
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
                    errors.Add(new Issue(path, $"{Brief(instance)} is not a {Canonical(format)}"));
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

        // The classic catastrophic shape: a group whose whole content is ONE quantified atom (a
        // character, an escape or a class) and which is quantified again - ^(a+)+$, (\d*)*, ([a-z]+){2,},
        // (x{2,})+ - backtracks exponentially; refused by every engine before it runs (this one also
        // runs under RegexTimeout). A group that ends in a literal - ([a-z]+/)* - is NOT this shape:
        // every iteration must consume the literal, so the split is unambiguous and linear.
        private const string Quantifier = @"(?:[+*]|\{[0-9]+(?:,[0-9]*)?\})";
        private static readonly Regex NestedQuantifier = new(
            @"\((?:\?:)?(?:\\.|\[(?:[^\]\\]|\\.)*\]|[^()\\\[\]])" + Quantifier + @"\??\)" + Quantifier,
            RegexOptions.ECMAScript, RegexTimeout);

        private static bool IsDateTime(string value) =>
            DateTimeShape.IsMatch(value)
            && DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out _);

        // Constructs .NET, Python and ECMA-262 do not share; refused by name so both engines agree.
        private static readonly string[] NonPortableRegexConstructs =
        {
            "\\A", "\\Z", "\\z", "\\G", "(?<=", "(?<!", "\\p{", "\\P{", "(?i)", "(?m)", "(?s)", "(?x)", "(?#",
        };

        private static void ValidateNumber(JsonElement schema, JsonElement instance, string path, List<Issue> errors)
        {
            var value = instance.GetDouble();
            if (schema.TryGetProperty("minimum", out var minimum) && value < minimum.GetDouble())
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is less than the minimum of {Canonical(minimum)}"));
            }
            if (schema.TryGetProperty("maximum", out var maximum) && value > maximum.GetDouble())
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is greater than the maximum of {Canonical(maximum)}"));
            }
            if (schema.TryGetProperty("exclusiveMinimum", out var exclusiveMinimum) && value <= exclusiveMinimum.GetDouble())
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is less than or equal to the minimum of {Canonical(exclusiveMinimum)}"));
            }
            if (schema.TryGetProperty("exclusiveMaximum", out var exclusiveMaximum) && value >= exclusiveMaximum.GetDouble())
            {
                errors.Add(new Issue(path, $"{Brief(instance)} is greater than or equal to the maximum of {Canonical(exclusiveMaximum)}"));
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
                if (patternProperties.ValueKind == JsonValueKind.Object)
                {
                    foreach (var candidate in patternProperties.EnumerateObject())
                    {
                        if (Compile(JsonDocument.Parse($"\"{JsonEncodedText.Encode(candidate.Name)}\"").RootElement, path).IsMatch(member.Name))
                        {
                            matched = true;
                            Validate(candidate.Value, member.Value, child, errors);
                        }
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
                    using var nameDocument = JsonDocument.Parse($"\"{JsonEncodedText.Encode(member.Name)}\"");
                    Validate(propertyNames, nameDocument.RootElement.Clone(), child, errors);
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
            var value = number.GetDouble();
            return !double.IsInfinity(value) && Math.Floor(value) == value;
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

        private static bool JsonEquals(JsonElement left, JsonElement right)
        {
            if (left.ValueKind == JsonValueKind.Number && right.ValueKind == JsonValueKind.Number)
            {
                return left.GetDouble() == right.GetDouble();
            }
            if (left.ValueKind is JsonValueKind.True or JsonValueKind.False
                || right.ValueKind is JsonValueKind.True or JsonValueKind.False)
            {
                return left.ValueKind == right.ValueKind;
            }
            return Canonical(left) == Canonical(right);
        }

        /// <summary>Canonical form for messages: a whole manifest quoted back is noise, not a hint.</summary>
        private static string Brief(JsonElement element)
        {
            const int limit = 120;
            var text = Canonical(element);
            return text.Length <= limit ? text : text[..(limit - 3)] + "...";
        }

        /// <summary>Compact JSON with object keys sorted, so equality and messages are order-independent.</summary>
        private static string Canonical(JsonElement element)
        {
            switch (element.ValueKind)
            {
                case JsonValueKind.Object:
                    var members = element.EnumerateObject()
                        .OrderBy(member => member.Name, StringComparer.Ordinal)
                        .Select(member => JsonSerializer.Serialize(member.Name) + ":" + Canonical(member.Value));
                    return "{" + string.Join(",", members) + "}";
                case JsonValueKind.Array:
                    return "[" + string.Join(",", element.EnumerateArray().Select(Canonical)) + "]";
                case JsonValueKind.String:
                    // Compare the VALUE, not the source text: "\u0041" and "A" are the same string.
                    return JsonSerializer.Serialize(element.GetString());
                case JsonValueKind.Number:
                    // 1.0 and 1 are the same number to JSON Schema.
                    return element.GetDouble().ToString("R", CultureInfo.InvariantCulture);
                default:
                    return element.GetRawText();
            }
        }
    }
}
