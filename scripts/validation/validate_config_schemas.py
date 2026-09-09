#!/usr/bin/env python3
"""Validate HELIOS config manifests against their JSON Schemas.

The map of manifest -> schema is config/schemas/manifests.json (one place; the
helios_config_validate MCP tool reads the same file). Every schema under
config/schemas/ is draft 2020-12.

Engine: python-jsonschema when it is importable, otherwise a built-in validator
covering the keyword subset the repo's schemas use (type, required, enum, const,
pattern, format date / date-time, min/max length, min/max items, uniqueItems,
minimum / maximum, properties, patternProperties, additionalProperties,
propertyNames, min/maxProperties, items, contains, $ref, allOf / anyOf / oneOf /
not, if / then / else). The fallback is the engine CI actually runs (ubuntu
runners ship PyYAML but not jsonschema), so it refuses schemas that use a keyword
it does not implement instead of silently skipping the check.

Usage:
    validate_config_schemas.py                         # every mapped manifest
    validate_config_schemas.py config/github/labels.json
    validate_config_schemas.py --schema config/schemas/github-labels.schema.json draft.json
    validate_config_schemas.py --list                  # print the map
    validate_config_schemas.py --engine builtin        # force the fallback
    validate_config_schemas.py --json                  # one JSON object on stdout

Exit codes: 0 = every manifest valid; 1 = at least one invalid; 2 = an input
could not be read, a schema is malformed / unsupported, or a manifest has no
mapping and no --schema was given.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as _dt
import decimal
import json
import math
import os
import re
import signal
import subprocess
import threading
from urllib.parse import urlsplit
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

try:
    import jsonschema
except ModuleNotFoundError:  # pragma: no cover - exercised on runners without the package
    jsonschema = None

REPO_ROOT = Path(__file__).resolve().parents[2]
MAPPING_FILE = Path("config") / "schemas" / "manifests.json"


class SchemaError(Exception):
    """The schema itself is malformed or uses a keyword the built-in engine lacks."""


@dataclass(frozen=True)
class Issue:
    path: str
    message: str


@dataclass(frozen=True)
class Mapping:
    manifest: str
    schema: str
    consumer: str = ""


@dataclass
class Result:
    manifest: str
    schema: str
    valid: bool
    issues: list[Issue] = field(default_factory=list)
    engine: str = "builtin"


# --------------------------------------------------------------------------------------
# Built-in draft 2020-12 subset
# --------------------------------------------------------------------------------------

_ANNOTATIONS = {
    "$schema", "$id", "$comment", "$defs", "definitions", "title", "description",
    "default", "examples", "deprecated", "readOnly", "writeOnly",
}
_SUPPORTED = {
    "$ref", "type", "enum", "const", "properties", "patternProperties",
    "additionalProperties", "propertyNames", "required", "minProperties", "maxProperties",
    "items", "contains", "minItems", "maxItems", "uniqueItems", "minLength", "maxLength",
    "pattern", "format", "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum",
    "allOf", "anyOf", "oneOf", "not", "if", "then", "else",
}
_TYPE_NAMES = ("null", "boolean", "object", "array", "number", "integer", "string")


# A JSON number is a decimal token, and json's float loses it: 9007199254740993.0 and
# 9007199254740992.0 become one float, 1e-324 becomes zero. load_json parses every non-integer
# token as a Decimal instead (parse_float below), so the Python engine compares what the manifest
# wrote - exactly as the C# twin's CanonicalNumber does.
_NUMBER_TYPES = (int, float, decimal.Decimal)


def _is_integer(value: Any) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return True
    if isinstance(value, decimal.Decimal):
        return value == value.to_integral_value()
    return isinstance(value, float) and value.is_integer()


def _type_of(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, _NUMBER_TYPES):
        return "integer" if _is_integer(value) else "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    raise SchemaError(f"unsupported instance value {value!r}")


def _matches_type(value: Any, expected: str) -> bool:
    actual = _type_of(value)
    if expected == "number":
        return actual in ("number", "integer")
    if expected == "integer":
        return actual == "integer"
    return actual == expected


def _number_text(value: Any) -> str:
    """A number as a message should read it: the way the manifest wrote it."""
    return str(value) if isinstance(value, decimal.Decimal) else json.dumps(value)


def _canonical(value: Any) -> str:
    """Compact JSON with object keys sorted — the form a message quotes back."""
    if isinstance(value, bool) or value is None:
        return json.dumps(value)
    if isinstance(value, _NUMBER_TYPES):
        return _number_text(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "[" + ",".join(_canonical(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{" + ",".join(f"{json.dumps(key)}:{_canonical(item)}"
                              for key, item in sorted(value.items())) + "}"
    return json.dumps(value)


# The exponent both engines hold, applied to the LITERAL in the token - the one place the two
# engines can agree without either reproducing the other's normalization. It is also exactly where
# decimal.Decimal's own constructor stops on this platform, so the explicit check only makes that
# boundary the same everywhere rather than a property of the local build. Keep it equal to
# `exponentLimit` in src/mcp/HELIOS.Mcp/JsonSchemaLite.cs.
_MAX_EXPONENT = 999_999_999_999_999_999
_EXPONENT_IN_TOKEN = re.compile(r"[eE]([+-]?[0-9]+)\Z")


def _exponent_out_of_range(written: str) -> bool:
    """The exponent literal's magnitude is past _MAX_EXPONENT.

    Leading zeros are stripped before the digits are counted, and the count decides the answer for
    anything long: int() on a 4,300-digit string is refused outright by CPython, and `1e-000...01`
    is the exponent -1 however many zeros precede it - which .NET's long.TryParse reads without
    complaint, so an int() here would have refused a token the C# twin accepts.
    """
    digits = written.lstrip("+-").lstrip("0") or "0"
    return len(digits) > len(str(_MAX_EXPONENT)) or int(digits) > _MAX_EXPONENT


def _normalize_number(value: Any) -> tuple[bool, str, int]:
    """(negative, significant digits, power of ten) - the C# twin's TryNormalizeNumber.

    1, 1.0 and 1e0 normalize alike; 9007199254740992 and 9007199254740993 do not, and neither do
    0 and 1e-29. No digits means zero, whatever exponent the token carried.
    """
    if isinstance(value, decimal.Decimal):
        exact = value
    elif isinstance(value, float):
        exact = decimal.Decimal(repr(value))   # the shortest token that round-trips, not the binary tail
    else:
        exact = decimal.Decimal(value)
    sign, digits, exponent = exact.as_tuple()
    text = "".join(str(digit) for digit in digits).lstrip("0")
    stripped = text.rstrip("0")
    return bool(sign), stripped, int(exponent) + (len(text) - len(stripped))


def _number_key(value: Any) -> str:
    """A number's equality key: sign, significant digits, and the power of ten that scales them.

    The C# twin's CanonicalNumber produces the same shape, so the two engines judge one manifest
    alike.
    """
    negative, digits, exponent = _normalize_number(value)
    if not digits:
        return "0"
    return f"{'-' if negative else ''}{digits}e{exponent}"


def _canonical_key(value: Any) -> str:
    """The structural equality key: _canonical, with numbers compared as values."""
    if isinstance(value, bool) or value is None:
        return json.dumps(value)
    if isinstance(value, _NUMBER_TYPES):
        return _number_key(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "[" + ",".join(_canonical_key(item) for item in value) + "]"
    if isinstance(value, dict):
        return "{" + ",".join(f"{json.dumps(key)}:{_canonical_key(item)}"
                              for key, item in sorted(value.items())) + "}"
    return json.dumps(value)


def _brief(value: Any, limit: int = 120) -> str:
    """Canonical form for messages: a whole manifest quoted back is noise, not a hint."""
    text = _canonical(value)
    return text if len(text) <= limit else text[: limit - 3] + "..."


def _json_equal(left: Any, right: Any) -> bool:
    if isinstance(left, bool) or isinstance(right, bool):
        return isinstance(left, bool) and isinstance(right, bool) and left == right
    if isinstance(left, _NUMBER_TYPES) and isinstance(right, _NUMBER_TYPES):
        return _number_key(left) == _number_key(right)
    return _canonical_key(left) == _canonical_key(right)


def _check_date(value: str) -> bool:
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        return False
    try:
        _dt.date.fromisoformat(value)
    except ValueError:
        return False
    return True


# RFC 3339: date, 'T', hh:mm:ss (fraction optional) and a MANDATORY offset (Z or +-hh:mm).
# A missing offset or missing seconds is what jsonschema + rfc3339-validator reject, so the
# dependency-free engine and the C# twin reject it too.
_DATE_TIME_SHAPE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})$")

# Constructs .NET, Python and ECMA-262 do not share; refused by name so the C# engine
# (JsonSchemaLite, ECMAScript mode) and this one accept exactly the same patterns.
_NON_PORTABLE_REGEX = ("\\A", "\\Z", "\\z", "\\G", "(?<=", "(?<!", "\\p{", "\\P{", "(?i)", "(?m)", "(?s)", "(?x)", "(?#")

# The two catastrophic shapes, found by walking the pattern rather than by matching it with
# another regex (a regex cannot skip character classes or count alternatives reliably):
#
#   1. a group whose whole content is ONE quantified atom, quantified again - ^(a+)+$, (\d*)*,
#      ([a-z]+){2,}, (x{2,})+, (a+?)+;
#   2. a group carrying a top-level alternation, quantified - ^(a|aa)+$, (?:ab|a)*, (a|aa|aaa)+ -
#      whose alternatives can match the same text.
#
# Both backtrack exponentially on a non-matching string and Python's re has no timeout, so they
# are refused before evaluation (the C# twin refuses the identical shapes and also runs under a
# 2 s timeout). A group that must consume a literal each iteration - ([a-z]+/)*, (?:ab*)*c - is
# unambiguous and linear; a bounded quantifier - (a|b)?, (dev|prod) - is safe; and a '(' or '|'
# INSIDE a character class - [(a|b)+] - is a literal, not structure.


def _quantifier_at(pattern: str, index: int) -> tuple[int, bool]:
    """(length, unbounded_or_above_one) of the quantifier at `index`; (0, False) if none.
    '?' and '{0,1}' / '{1}' repeat at most once, so they cannot multiply a group's paths."""
    if index >= len(pattern):
        return 0, False
    char = pattern[index]
    if char in "+*":
        return 1, True
    if char == "?":
        return 1, False
    if char != "{":
        return 0, False
    # Scan forward to the first character that cannot be part of a repetition count, instead of
    # searching the rest of the pattern for '}': str.find is O(n) per '{', which made this
    # preflight quadratic on a pattern of unmatched braces (an 800 KB schema outran the deadline
    # before compilation ever started). Each character is consumed by at most one scan, so the
    # walk stays linear however the braces are arranged - and a body of leading zeros is still
    # read as the count it is.
    cursor = index + 1
    length = len(pattern)
    while cursor < length and pattern[cursor] in "0123456789,":
        cursor += 1
    if cursor >= length or pattern[cursor] != "}":
        return 0, False
    close = cursor
    body = pattern[index + 1:close]
    low, comma, high = body.partition(",")
    if not _is_count(low) or (comma and high and not _is_count(high)):
        return 0, False  # not a quantifier, just a literal brace
    if not comma:                  # {n}
        return close - index + 1, _count_value(low) > 1
    if not high:                   # {n,}
        return close - index + 1, True
    return close - index + 1, _count_value(high) > 1


# .NET refuses a repetition count above this outright ("Quantifier and capture group numbers
# must be less than or equal to Int32.MaxValue"), while Python compiles it, so a pattern carrying
# one is usable in CI and unusable through helios_config_validate.
_MAX_REPETITION = 2_147_483_647


def _omitted_lower_bound(pattern: str, index: int) -> bool:
    """`{,n}` or `{,}` at `index`: Python reads them as {0,n} and {0,}; .NET reads literal
    characters.

    So `^a{,3}$` matches "aa" in one engine and nothing but the text "a{,3}" in the other - and
    `a{,3}+` is a possessive quantifier that _quantifier_at, which needs a lower bound, never sees.
    """
    cursor = index + 1
    if cursor >= len(pattern) or pattern[cursor] != ",":
        return False
    cursor += 1
    while cursor < len(pattern) and pattern[cursor] in "0123456789":
        cursor += 1
    return cursor < len(pattern) and pattern[cursor] == "}"


def _count_above(text: str, ceiling: int) -> bool:
    """The count spelled by `text` exceeds `ceiling`, without building a huge int for a huge one."""
    stripped = text.lstrip("0") or "0"
    return len(stripped) > len(str(ceiling)) or int(stripped) > ceiling


def _oversized_count(pattern: str, index: int) -> bool:
    """A `{n}` / `{n,}` / `{n,m}` at `index` whose count is past what .NET's parser accepts."""
    cursor = index + 1
    length = len(pattern)
    while cursor < length and pattern[cursor] in "0123456789,":
        cursor += 1
    if cursor >= length or pattern[cursor] != "}":
        return False
    low, comma, high = pattern[index + 1:cursor].partition(",")
    parts = (low, high) if comma else (low,)
    return any(_is_count(part) and _count_above(part, _MAX_REPETITION) for part in parts)


def _is_count(text: str) -> bool:
    return bool(text) and all(digit in "0123456789" for digit in text)


def _count_value(text: str) -> int:
    """A repetition count, or 2 when it is longer than any engine could hold.

    int() on a very long digit string is both slow and refused outright past CPython's 4300-digit
    limit, and every such count multiplies anyway - so the shape reads as "more than one" without
    the conversion. Leading zeros are stripped first: {0000000000000000000000000000000000000002}
    is the count two, however it is spelled.
    """
    stripped = text.lstrip("0") or "0"
    return int(stripped) if len(stripped) <= 18 else 2


def _catastrophic_shape(pattern: str) -> str | None:
    """The reason `pattern` can backtrack exponentially, or None."""
    frames: list[dict[str, int]] = []
    current = {"alternation": 0, "atoms": 0, "quantifiers": 0}
    index = 0
    length = len(pattern)
    while index < length:
        char = pattern[index]
        if char == "\\":
            index += 2
            current["atoms"] += 1
            continue
        if char == "[":
            cursor = index + 1
            if cursor < length and pattern[cursor] == "^":
                cursor += 1
            if cursor < length and pattern[cursor] == "]":   # a leading ']' is a literal
                cursor += 1
            while cursor < length and pattern[cursor] != "]":
                cursor += 2 if pattern[cursor] == "\\" else 1
            index = cursor + 1
            current["atoms"] += 1
            continue
        if char == "(":
            frames.append(current)
            current = {"alternation": 0, "atoms": 0, "quantifiers": 0}
            index += 1
            if pattern.startswith("?:", index):
                index += 2
            elif index < length and pattern[index] == "?":
                index += 1
                while index < length and pattern[index] in "=!<":
                    index += 1
            continue
        if char == ")":
            inner = current
            current = frames.pop() if frames else {"alternation": 0, "atoms": 0, "quantifiers": 0}
            index += 1
            size, multiplying = _quantifier_at(pattern, index)
            if size:
                index += size
                if index < length and pattern[index] == "?":
                    index += 1                                # lazy marker
                if multiplying:
                    if inner["alternation"]:
                        return "a quantified group carries an alternation (ambiguous backtracking); write a character class or split the pattern"
                    if inner["atoms"] == 1 and inner["quantifiers"] == 1:
                        return "a quantified group is itself quantified (catastrophic backtracking)"
                current["quantifiers"] += 1
            current["atoms"] += 1
            continue
        if char == "|":
            current["alternation"] = 1
            current["atoms"] = 0          # each alternative is measured on its own
            current["quantifiers"] = 0
            index += 1
            continue
        if char in "^$":
            index += 1                    # an anchor is not an atom
            continue
        size, _multiplying = _quantifier_at(pattern, index)
        if size and current["atoms"]:
            index += size
            if index < length and pattern[index] == "?":
                index += 1
            current["quantifiers"] += 1
            continue
        index += 1
        current["atoms"] += 1
    return None

# Nesting deeper than this means a $ref cycle that never descends into the instance
# ("$ref": "#", or two $defs pointing at each other); real schemas nest a few dozen levels.
_MAX_DEPTH = 256

_INTEGER_KEYWORDS = ("minLength", "maxLength", "minItems", "maxItems", "minProperties", "maxProperties")
_NUMBER_KEYWORDS = ("minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum")

# Every regex operation runs under a bound. Enumerating catastrophic shapes cannot be the
# guarantee - a scanner only refuses what it names, and ^(a+a+)+$ is not one of them - while a
# clock bounds every pattern, known shape or not. Two mechanisms, chosen by what the interpreter
# can actually deliver here:
#   * a SIGALRM deadline when the signal really can arrive - POSIX, the main thread, unblocked,
#     and no alarm of the caller's to clobber. That is CI, the CLI and the sweep.
#   * process isolation otherwise (Windows, a worker thread): the whole pass runs in a child
#     interpreter that is killed when the budget expires. Ending THIS process instead - what a
#     faulthandler watchdog does - would take a caller's service down with the bad pattern.
# The per-match budget matches JsonSchemaLite's RegexTimeout so both engines give up at the same
# point; a whole pass gets the longer one, since one deadline covers every match in it.
# A resource guard, not a rule about schemas: past this many keyword evaluations for ONE instance
# the walk is pathological rather than large. Memoization (below) already collapses the shape that
# used to explode - an allOf repeating the $ref beneath it - so this ceiling sits far above any
# instance a manifest could plausibly hold, and the C# twin keeps its own, lower one for a server
# that answers a single request per process.
_MAX_EVALUATIONS = 1_000_000
_MATCH_BUDGET_SECONDS = 2.0
_LIBRARY_PASS_BUDGET_SECONDS = 10.0
_ISOLATION_ENV = "HELIOS_SCHEMA_VALIDATION_ISOLATED"


class _MatchTimeout(Exception):
    """A regex operation outran its budget."""


# Per THREAD: a deadline armed by one thread bounds only that thread's work, so treating another
# thread's guard as an enclosing one would leave the second thread running with no bound at all.
_deadline = threading.local()


def _alarm_deliverable() -> bool:
    """Whether a SIGALRM deadline can be armed here without lying about it or clobbering a caller."""
    if not (hasattr(signal, "setitimer") and hasattr(signal, "SIGALRM")):
        return False                                    # Windows has neither
    if threading.current_thread() is not threading.main_thread():
        return False                                    # only the main thread runs signal handlers
    if signal.getitimer(signal.ITIMER_REAL)[0]:
        return False                                    # the caller armed ITIMER_REAL; not ours to take
    if hasattr(signal, "pthread_sigmask") and signal.SIGALRM in signal.pthread_sigmask(signal.SIG_BLOCK, set()):
        return False                                    # blocked: the alarm would never be delivered
    return True


@contextlib.contextmanager
def _match_deadline(budget: float = _MATCH_BUDGET_SECONDS) -> Any:
    """Bound the enclosed regex work with SIGALRM; nested uses ride on the outermost deadline.

    Where no alarm can be delivered this yields unguarded on purpose: the caller is either inside
    the isolating child (whose parent enforces the budget by killing it) or has reached the
    documented last resort in validate_instance, which says so.
    """
    if getattr(_deadline, "held", False) or not _alarm_deliverable():
        yield
        return
    _deadline.held = True
    try:
        def _fire(_signum: int, _frame: Any) -> None:
            raise _MatchTimeout

        previous = signal.signal(signal.SIGALRM, _fire)
        signal.setitimer(signal.ITIMER_REAL, budget)
        try:
            yield
        finally:
            # Cancel first, restore always: an alarm delivered between the two raises _MatchTimeout
            # out of setitimer, and without the inner try this module's handler would stay
            # installed in the caller's process.
            try:
                signal.setitimer(signal.ITIMER_REAL, 0)
            finally:
                signal.signal(signal.SIGALRM, previous)
    finally:
        _deadline.held = False


def _bounded(what: str, where: str, work: Callable[[], Any]) -> Any:
    """Run one regex operation under the deadline; a timeout is the schema's verdict."""
    try:
        with _match_deadline():
            return work()
    except _MatchTimeout:
        raise SchemaError(
            f"{where}: {what} did not finish within {_MATCH_BUDGET_SECONDS:g}s and was abandoned; "
            "the pattern backtracks on this input - rewrite it (a character class, or a literal "
            "that must be consumed each repetition, instead of a quantified group)") from None


def _python_only_construct(pattern: str) -> str | None:
    """The reason this pattern means different things to the three engines, or None.

    Python 3.11 added possessive quantifiers (a++, a*+, a?+, a{2,3}+) and atomic groups ((?>...)),
    it reads `{,n}` and `{,}` as repetitions where .NET reads literal characters, and it compiles a
    repetition count .NET refuses outright. Each of those makes a schema usable in CI and unusable
    through helios_config_validate. Found by walking the pattern rather than by searching for a
    substring, so a literal '\\++' - one or more plus signs - and a character class '[(?>]' are read
    as what they are and stay legal.
    """
    index = 0
    length = len(pattern)
    while index < length:
        char = pattern[index]
        if char == "\\":
            index += 2
            continue
        if char == "[":
            cursor = index + 1
            if cursor < length and pattern[cursor] == "^":
                cursor += 1
            if cursor < length and pattern[cursor] == "]":   # a leading ']' is a literal
                cursor += 1
            while cursor < length and pattern[cursor] != "]":
                cursor += 2 if pattern[cursor] == "\\" else 1
            index = cursor + 1
            continue
        if char == "(" and pattern.startswith("?>", index + 1):
            return "an atomic group ('(?>') is outside the portable (ECMA-262) regex subset"
        if char == "{" and _omitted_lower_bound(pattern, index):
            return "an omitted lower bound ('{,n}') is outside the portable (ECMA-262) regex subset"
        if char == "{" and _oversized_count(pattern, index):
            return f"a repetition count above {_MAX_REPETITION} is outside the range every engine holds"
        size, _ = _quantifier_at(pattern, index)
        if size:
            index += size
            if index < length and pattern[index] == "+":
                return "a possessive quantifier ('++', '*+', '?+', '{n,m}+') is outside the portable (ECMA-262) regex subset"
            if index < length and pattern[index] == "?":
                index += 1                                    # lazy: legal in both dialects
            continue
        index += 1
    return None


def _unsafe_pattern(pattern: str) -> str | None:
    """The reason a pattern is refused by every engine, or None when it is fine.

    An early refusal with a message that names the mistake, NOT the safety guarantee: a scanner
    only knows the shapes it enumerates. The guarantee is _match_deadline, which bounds every
    match whatever the pattern looks like."""
    unportable = next((token for token in _NON_PORTABLE_REGEX if token in pattern), None)
    if unportable is not None:
        return f"'{unportable}' is outside the portable (ECMA-262) regex subset"
    python_only = _python_only_construct(pattern)
    if python_only is not None:
        return python_only
    return _catastrophic_shape(pattern)


def _check_date_time(value: str) -> bool:
    # RFC 3339 shape first (fromisoformat is lenient about separators), then a real clock check.
    if not _DATE_TIME_SHAPE.match(value):
        return False
    # The shape fixes each field's width, not its range, and fromisoformat normalizes an offset of
    # +15:60 into +16:00 rather than refusing it. The C# twin reads the digits; so does this.
    if value[-6] in "+-" and not (int(value[-5:-3]) <= 23 and int(value[-2:]) <= 59):
        return False
    try:
        _dt.datetime.fromisoformat(value.replace("z", "Z").replace("Z", "+00:00"))
    except ValueError:
        return False
    return True


_FORMATS: dict[str, Callable[[str], bool]] = {
    "date": _check_date,
    "date-time": _check_date_time,
}


class MiniValidator:
    """Dependency-free validator for the keyword subset listed in the module docstring.

    Error messages follow python-jsonschema's wording where a message is likely to be
    matched in a test, so the two engines read the same in CI logs.
    """

    def __init__(self, schema: Any) -> None:
        self.root = schema
        self._regex: dict[str, re.Pattern[str]] = {}
        self._depth = 0
        self._schema_depth = 0
        self._evaluations = 0
        self._memo: dict[tuple[int, int, str], list[Issue]] = {}
        # The self-check walks attacker-supplied structure too, so it runs under the same clock
        # as a validation pass rather than only bounding the regex work inside it.
        with _match_deadline(_LIBRARY_PASS_BUDGET_SECONDS):
            self.check_schema()

    # -- schema self-check ------------------------------------------------------------

    def check_schema(self) -> None:
        self._walk_schema(self.root, "#")

    def _walk_schema(self, node: Any, where: str) -> None:
        # The self-check recurses through the schema's own structure, and CountEvaluation-style
        # budgets bound the NUMBER of nodes, not the depth of the call stack: a few thousand
        # nested `not` or `items` raise RecursionError here, which is a traceback out of
        # validate_all.py's whole sweep rather than a verdict about one schema. The C# twin
        # (JsonSchemaLite.WalkSchema) would die with an uncatchable StackOverflowException, so
        # both guard the walk at the same depth the instance walk uses.
        self._schema_depth += 1
        try:
            if self._schema_depth > _MAX_DEPTH:
                raise SchemaError(f"{where}: schema nesting deeper than {_MAX_DEPTH} levels - "
                                  "more structure than any manifest schema needs")
            self._walk_schema_here(node, where)
        finally:
            self._schema_depth -= 1

    def _walk_schema_here(self, node: Any, where: str) -> None:
        if isinstance(node, bool):
            return
        if not isinstance(node, dict):
            raise SchemaError(f"{where}: a schema must be an object or a boolean")
        for key, value in node.items():
            if key == "$schema" and where != "#":
                # python-jsonschema re-selects a validator for a subschema that declares its own
                # dialect, which would drop this module's regex and number rules for that subtree.
                # No shipped schema does it, and the built-in engine has no second dialect to give.
                raise SchemaError(f"{where}/$schema: a dialect may only be declared at the root of a schema")
            if key in _ANNOTATIONS:
                if key in ("$defs", "definitions") and isinstance(value, dict):
                    for name, sub in value.items():
                        self._walk_schema(sub, f"{where}/{key}/{name}")
                continue
            if key not in _SUPPORTED:
                raise SchemaError(
                    f"{where}: keyword '{key}' is not implemented by the built-in validator; "
                    "extend MiniValidator (and JsonSchemaLite.cs) or drop the keyword")
            if key in ("properties", "patternProperties"):
                if not isinstance(value, dict):
                    raise SchemaError(f"{where}/{key}: must be an object")
                for name, sub in value.items():
                    # The KEY of a patternProperties entry is itself a regex, and it is the one
                    # thing a walk of the subschemas never reaches: with an instance that has no
                    # properties, nothing else would ever compile "[" and the schema would pass as
                    # usable. python-jsonschema refuses it at check_schema; so does this now.
                    if key == "patternProperties":
                        self._compile(name, f"{where}/{key}/{name}")
                    self._walk_schema(sub, f"{where}/{key}/{name}")
            elif key in ("additionalProperties", "propertyNames", "items", "contains",
                         "not", "if", "then", "else"):
                self._walk_schema(value, f"{where}/{key}")
            elif key in ("allOf", "anyOf", "oneOf"):
                if not isinstance(value, list) or not value:
                    raise SchemaError(f"{where}/{key}: must be a non-empty array")
                for index, sub in enumerate(value):
                    self._walk_schema(sub, f"{where}/{key}/{index}")
            elif key == "type":
                names = value if isinstance(value, list) else [value]
                if not names or not all(isinstance(name, str) for name in names):
                    raise SchemaError(f"{where}/type: must be a type name or a non-empty array of type names")
                for name in names:
                    if name not in _TYPE_NAMES:
                        raise SchemaError(f"{where}/type: unknown type {name!r}")
            elif key == "pattern":
                self._compile(value, where)
            elif key == "$ref":
                self._resolve(value, where)
            # Keyword VALUES are checked here, once, so a malformed schema is a SchemaError
            # (exit 2 / "not usable") instead of a TypeError deep inside validation.
            elif key in _INTEGER_KEYWORDS:
                if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                    raise SchemaError(f"{where}/{key}: must be a non-negative integer")
            elif key in _NUMBER_KEYWORDS:
                if isinstance(value, bool) or not isinstance(value, _NUMBER_TYPES):
                    raise SchemaError(f"{where}/{key}: must be a number")
            elif key == "required":
                if not isinstance(value, list) or not all(isinstance(name, str) for name in value):
                    raise SchemaError(f"{where}/required: must be an array of property names")
            elif key == "enum":
                if not isinstance(value, list) or not value:
                    raise SchemaError(f"{where}/enum: must be a non-empty array")
            elif key == "uniqueItems":
                if not isinstance(value, bool):
                    raise SchemaError(f"{where}/uniqueItems: must be a boolean")
            elif key == "format":
                if not isinstance(value, str):
                    raise SchemaError(f"{where}/format: must be a string")
                # Unknown formats are annotations per the spec; nothing else to assert.

    def _compile(self, pattern: Any, where: str) -> re.Pattern[str]:
        if not isinstance(pattern, str):
            raise SchemaError(f"{where}/pattern: must be a string")
        compiled = self._regex.get(pattern)
        if compiled is None:
            reason = _unsafe_pattern(pattern)
            if reason is not None:
                raise SchemaError(f"{where}/pattern: {reason} in {pattern!r}")
            try:
                # Bounded like a match: a{999999999999999999999999} raises OverflowError (not
                # re.error) out of the C parser, and a large-but-legal repeat count builds a
                # program big enough to matter.
                # re.ASCII: JSON Schema patterns are ECMA-262, where \d \w \s and their
                # negations are ASCII. Python's default is Unicode, so `^\d+$` would accept an
                # Arabic-Indic digit here and be refused by the C# engine's ECMAScript mode - the
                # same manifest, two verdicts. The shipped schemas use \s and \S, which differ the
                # same way for a non-breaking space.
                compiled = _bounded(f"compiling {pattern!r}", f"{where}/pattern",
                                    lambda: re.compile(pattern, re.ASCII))
            except (re.error, OverflowError, MemoryError, RecursionError) as exc:
                raise SchemaError(f"{where}/pattern: invalid regex {pattern!r}: {exc}") from exc
            self._regex[pattern] = compiled
        return compiled

    # A $ref may only NAME a definition - '#', '#/$defs/<name>' or '#/definitions/<name>' - and
    # not descend past one. Every other target is refused because the walk never reaches it:
    # annotations other than $defs and definitions are skipped, so `{"$ref": "#/default", ...}`
    # validated against a subschema whose keywords, patterns and numbers nothing had checked, and
    # `#/$defs/a/default` reached the same place one level lower. Refusing the shape closes both
    # without walking anything twice, and every shipped schema already writes #/$defs/<name>.
    _REF_CONTAINERS = ("$defs", "definitions")

    def _resolve(self, ref: Any, where: str) -> Any:
        if not isinstance(ref, str) or not ref.startswith("#"):
            raise SchemaError(f"{where}/$ref: only local '#/...' references are supported, got {ref!r}")
        segments = ref[2:].split("/") if ref.startswith("#/") else []
        if ref != "#" and not (len(segments) == 2 and segments[0] in self._REF_CONTAINERS and segments[1]):
            raise SchemaError(f"{where}/$ref: {ref!r} must be '#' or name one definition "
                              "('#/$defs/<name>' or '#/definitions/<name>'); nothing deeper is "
                              "reached by the schema self-check")
        node: Any = self.root
        pointer = ref[1:]
        if pointer.startswith("/"):
            for token in pointer[1:].split("/"):
                token = token.replace("~1", "/").replace("~0", "~")
                if isinstance(node, dict) and token in node:
                    node = node[token]
                elif isinstance(node, list) and token.isdigit() and int(token) < len(node):
                    node = node[int(token)]
                else:
                    raise SchemaError(f"{where}/$ref: {ref!r} does not resolve")
        elif pointer:
            raise SchemaError(f"{where}/$ref: unsupported reference {ref!r}")
        return node

    # -- validation -------------------------------------------------------------------

    def charge(self, path: str) -> None:
        """Spend one unit of the work budget, or say which instance exhausted it.

        Public because the library engine's overridden keywords charge here too: python-jsonschema
        runs its own property and pattern loops, and work done there is work done against the same
        instance."""
        self._evaluations += 1
        if self._evaluations > _MAX_EVALUATIONS:
            raise SchemaError(
                f"{path}: this schema costs more than {_MAX_EVALUATIONS} keyword evaluations for one "
                "instance - more work than any manifest should need")

    def reset_budget(self) -> None:
        self._evaluations = 0

    def iter_errors(self, instance: Any) -> list[Issue]:
        errors: list[Issue] = []
        self._evaluations = 0
        self._memo = {}
        try:
            with _match_deadline(_LIBRARY_PASS_BUDGET_SECONDS):
                self._validate(self.root, instance, "$", errors)
        except _MatchTimeout:
            raise SchemaError(
                f"validating this instance did not finish within {_LIBRARY_PASS_BUDGET_SECONDS:g}s and was "
                "abandoned; the schema costs more work than any manifest should") from None
        return errors

    def is_valid(self, instance: Any) -> bool:
        return not self.iter_errors(instance)

    def _validate(self, schema: Any, instance: Any, path: str, errors: list[Issue]) -> None:
        # "$ref": "#" (or two $defs pointing at each other) recurses without ever descending
        # into the instance; a RecursionError would take the CLI - or validate_all.py's whole
        # sweep - down with a traceback. Past this depth the schema is the problem and says so.
        self._depth += 1
        self._evaluations += 1
        try:
            if self._depth > _MAX_DEPTH:
                raise SchemaError(f"{path}: schema nesting deeper than {_MAX_DEPTH} levels - a $ref cycle that never descends into the instance")
            if self._evaluations > _MAX_EVALUATIONS:
                raise SchemaError(
                    f"{path}: this schema costs more than {_MAX_EVALUATIONS} keyword evaluations for one "
                    "instance - more work than any manifest should need")
            # The same schema node against the same instance node always gives the same answer, so
            # it is evaluated once. That is what stops an allOf which repeats the $ref beneath it
            # from doubling the work at every level (2**depth evaluations of identical pairs) while
            # leaving ordinary work - every array item a distinct pair - untouched. Both objects are
            # held by the documents being walked, so their ids are stable for this pass.
            key = (id(schema), id(instance), path)
            remembered = self._memo.get(key)
            if remembered is not None:
                errors.extend(remembered)
                return
            found: list[Issue] = []
            self._validate_here(schema, instance, path, found)
            self._memo[key] = found
            errors.extend(found)
        finally:
            self._depth -= 1

    def _validate_here(self, schema: Any, instance: Any, path: str, errors: list[Issue]) -> None:
        if schema is True:
            return
        if schema is False:
            errors.append(Issue(path, "False schema does not allow " + _brief(instance)))
            return

        if "$ref" in schema:
            self._validate(self._resolve(schema["$ref"], "#"), instance, path, errors)

        if "type" in schema:
            names = schema["type"] if isinstance(schema["type"], list) else [schema["type"]]
            if not any(_matches_type(instance, name) for name in names):
                wanted = ", ".join(f"'{name}'" for name in names)
                errors.append(Issue(path, f"{_brief(instance)} is not of type {wanted}"))
                return  # type mismatches make the remaining keywords meaningless

        if "enum" in schema and not self._enum_contains(schema["enum"], instance, path):
            errors.append(Issue(path, f"{_brief(instance)} is not one of {_canonical(schema['enum'])}"))
        if "const" in schema and not _json_equal(instance, schema["const"]):
            errors.append(Issue(path, f"{_canonical(schema['const'])} was expected"))

        if isinstance(instance, str):
            self._validate_string(schema, instance, path, errors)
        elif isinstance(instance, _NUMBER_TYPES) and not isinstance(instance, bool):
            self._validate_number(schema, instance, path, errors)
        elif isinstance(instance, list):
            self._validate_array(schema, instance, path, errors)
        elif isinstance(instance, dict):
            self._validate_object(schema, instance, path, errors)

        for sub in schema.get("allOf", []):
            self._validate(sub, instance, path, errors)
        if "anyOf" in schema:
            self._validate_alternatives(schema["anyOf"], instance, path, errors, exactly_one=False)
        if "oneOf" in schema:
            self._validate_alternatives(schema["oneOf"], instance, path, errors, exactly_one=True)
        if "not" in schema and not self._errors_for(schema["not"], instance, path):
            errors.append(Issue(path, f"{_brief(instance)} should not be valid under {_brief(schema['not'])}"))
        if "if" in schema:
            branch = "then" if not self._errors_for(schema["if"], instance, path) else "else"
            if branch in schema:
                self._validate(schema[branch], instance, path, errors)

    def _enum_contains(self, options: Any, instance: Any, path: str) -> bool:
        """`instance` is one of `options` - _json_equal's rules, with the instance rendered once.

        A 200,000-entry enum against a 100 KB string used to render that string once per option:
        gigabytes of work charged as a single keyword evaluation. The comparison keys are computed
        on first use and reused, and every comparison spends a unit of the budget, so the cost of
        this keyword is bounded by the size of the documents. The C# twin caches the same two keys.
        """
        if not isinstance(options, list):
            return False
        # NOT dict.setdefault: it evaluates its default argument whether or not the key is
        # present, so the instance was still rendered once per option and the cache saved nothing.
        number_key: str | None = None
        canonical_key: str | None = None
        for option in options:
            self.charge(path)
            if isinstance(instance, bool) or isinstance(option, bool):
                if isinstance(instance, bool) and isinstance(option, bool) and instance == option:
                    return True
                continue
            if isinstance(instance, _NUMBER_TYPES) and isinstance(option, _NUMBER_TYPES):
                if number_key is None:
                    number_key = canonical_key if canonical_key is not None else _number_key(instance)
                if number_key == _number_key(option):
                    return True
                continue
            if canonical_key is None:
                # _canonical_key of a number IS its number key, so a mixed enum renders the
                # instance once rather than once per kind.
                canonical_key = number_key if number_key is not None else _canonical_key(instance)
            if canonical_key == _canonical_key(option):
                return True
        return False

    def _errors_for(self, schema: Any, instance: Any, path: str) -> list[Issue]:
        collected: list[Issue] = []
        self._validate(schema, instance, path, collected)
        return collected

    def _validate_alternatives(self, options: list[Any], instance: Any, path: str,
                               errors: list[Issue], exactly_one: bool) -> None:
        outcomes = [self._errors_for(option, instance, path) for option in options]
        matches = [index for index, outcome in enumerate(outcomes) if not outcome]
        if not matches:
            # Report the closest branch: the one with the fewest errors, preferring a branch
            # whose declared type matches the instance so an object is judged as an object.
            def rank(index: int) -> tuple[int, int]:
                option = options[index]
                declared = option.get("type") if isinstance(option, dict) else None
                if isinstance(option, dict) and "$ref" in option and declared is None:
                    resolved = self._resolve(option["$ref"], "#")
                    declared = resolved.get("type") if isinstance(resolved, dict) else None
                declared_list = declared if isinstance(declared, list) else [declared]
                type_penalty = 0 if any(
                    name is not None and _matches_type(instance, name) for name in declared_list) else 1
                return (type_penalty, len(outcomes[index]))

            best = min(range(len(options)), key=rank)
            keyword = "oneOf" if exactly_one else "anyOf"
            errors.append(Issue(path, f"{_brief(instance)} is not valid under any of the given schemas ({keyword})"))
            errors.extend(outcomes[best])
        elif exactly_one and len(matches) > 1:
            errors.append(Issue(path, f"{_brief(instance)} is valid under each of {len(matches)} oneOf schemas"))

    def _validate_string(self, schema: dict[str, Any], value: str, path: str, errors: list[Issue]) -> None:
        if "minLength" in schema and len(value) < schema["minLength"]:
            errors.append(Issue(path, f"{_brief(value)} is too short (minLength {schema['minLength']})"))
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            errors.append(Issue(path, f"{_brief(value)} is too long (maxLength {schema['maxLength']})"))
        if "pattern" in schema:
            compiled = self._compile(schema["pattern"], path)
            if not _bounded(f"matching {schema['pattern']!r}", path, lambda: compiled.search(value)):
                errors.append(Issue(path, f"{_brief(value)} does not match {_canonical(schema['pattern'])}"))
        checker = _FORMATS.get(schema.get("format", ""))
        if checker is not None and not checker(value):
            errors.append(Issue(path, f"{_brief(value)} is not a {_canonical(schema['format'])}"))

    @staticmethod
    def _validate_number(schema: dict[str, Any], value: float, path: str, errors: list[Issue]) -> None:
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(Issue(path, f"{_brief(value)} is less than the minimum of {schema['minimum']}"))
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(Issue(path, f"{_brief(value)} is greater than the maximum of {schema['maximum']}"))
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            errors.append(Issue(path, f"{_brief(value)} is less than or equal to the minimum of {schema['exclusiveMinimum']}"))
        if "exclusiveMaximum" in schema and value >= schema["exclusiveMaximum"]:
            errors.append(Issue(path, f"{_brief(value)} is greater than or equal to the maximum of {schema['exclusiveMaximum']}"))

    def _validate_array(self, schema: dict[str, Any], items: list[Any], path: str, errors: list[Issue]) -> None:
        if "minItems" in schema and len(items) < schema["minItems"]:
            errors.append(Issue(path, f"{_brief(items)} is too short (minItems {schema['minItems']})"))
        if "maxItems" in schema and len(items) > schema["maxItems"]:
            errors.append(Issue(path, f"{_brief(items)} is too long (maxItems {schema['maxItems']})"))
        if schema.get("uniqueItems"):
            seen: set[str] = set()
            for index, item in enumerate(items):
                key = _canonical_key(item)
                if key in seen:
                    # python-jsonschema reports the array, not the duplicate's index
                    errors.append(Issue(path, f"{_brief(items)} has non-unique elements"))
                    break
                seen.add(key)
        if "items" in schema:
            for index, item in enumerate(items):
                self._validate(schema["items"], item, f"{path}[{index}]", errors)
        if "contains" in schema and not any(
                not self._errors_for(schema["contains"], item, f"{path}[{index}]")
                for index, item in enumerate(items)):
            errors.append(Issue(path, f"{_brief(items)} does not contain items matching the given schema"))

    def _validate_object(self, schema: dict[str, Any], obj: dict[str, Any], path: str, errors: list[Issue]) -> None:
        for name in schema.get("required", []):
            if name not in obj:
                errors.append(Issue(path, f"'{name}' is a required property"))
        if "minProperties" in schema and len(obj) < schema["minProperties"]:
            errors.append(Issue(path, f"{_brief(obj)} does not have enough properties (minProperties {schema['minProperties']})"))
        if "maxProperties" in schema and len(obj) > schema["maxProperties"]:
            errors.append(Issue(path, f"{_brief(obj)} has too many properties (maxProperties {schema['maxProperties']})"))
        properties = schema.get("properties", {})
        pattern_properties = schema.get("patternProperties", {})
        unexpected: list[str] = []
        for name, value in obj.items():
            child = f"{path}.{name}"
            matched = False
            if name in properties:
                matched = True
                self._validate(properties[name], value, child, errors)
            for pattern, sub in pattern_properties.items():
                # Every attempt is charged: P patterns against N keys is P×N matches, and only
                # _validate used to touch the budget, so a large pair could spend millions of
                # matches against one instance evaluation. The C# twin charges the same way.
                self.charge(path)
                compiled = self._compile(pattern, path)
                if _bounded(f"matching {pattern!r}", path, lambda: compiled.search(name)):
                    matched = True
                    self._validate(sub, value, child, errors)
            if not matched and "additionalProperties" in schema:
                extra = schema["additionalProperties"]
                if extra is False:
                    unexpected.append(name)
                else:
                    self._validate(extra, value, child, errors)
            if "propertyNames" in schema:
                # python-jsonschema reports a bad key at the object, not at the key's own path
                self._validate(schema["propertyNames"], name, path, errors)
        if unexpected:
            listed = ", ".join(f"'{name}'" for name in unexpected)
            plural = "were" if len(unexpected) > 1 else "was"
            errors.append(Issue(path, f"Additional properties are not allowed ({listed} {plural} unexpected)"))


# --------------------------------------------------------------------------------------
# Engines
# --------------------------------------------------------------------------------------

def _format_json_path(parts: Any) -> str:
    rendered = "$"
    for part in parts:
        rendered += f"[{part}]" if isinstance(part, int) else f".{part}"
    return rendered


def available_engines() -> list[str]:
    return ["jsonschema", "builtin"] if jsonschema is not None else ["builtin"]


def _descend_alternatives(errors: Any) -> list[tuple[Any, str]]:
    """Mirror the built-in engine's closest-branch rule for python-jsonschema.

    jsonschema reports a failed anyOf / oneOf as one error at the alternatives' own path
    ("... is not valid under any of the given schemas") and keeps the per-branch errors in
    error.context. For a manifest that is "an object with a labels array OR a bare array",
    that top-level error names neither the bad key nor the bad value, so a typo in a closed
    object would be reported at `$`. This walks into the closest branch — the one whose
    declared type matches the instance (no `type` error at the alternatives' path),
    then the one with the fewest errors — exactly as MiniValidator._validate_alternatives
    does, so both engines name the same paths and the tests hold under either.
    """
    flattened: list[tuple[Any, str]] = []
    for error in errors:
        if not error.context:
            flattened.append((error, error.message))
            continue
        branches: dict[int, list[Any]] = {}
        for sub in error.context:
            branches.setdefault(int(sub.relative_schema_path[0]), []).append(sub)

        def rank(index: int) -> tuple[int, int]:
            subs = branches[index]
            here = list(error.absolute_path)
            type_penalty = 1 if any(
                sub.validator == "type" and list(sub.absolute_path) == here for sub in subs) else 0
            return (type_penalty, len(subs))

        best = min(branches, key=rank)
        flattened.append((error, f"{_brief(error.instance)} is not valid under any of the given schemas ({error.validator})"))
        flattened.extend(_descend_alternatives(branches[best]))
    return flattened


_CHILD_PROGRAM = """
import importlib.util, json, sys

spec = importlib.util.spec_from_file_location("_helios_config_schema_validator", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
request = json.loads(sys.stdin.read(), parse_float=module._exact_number,
                     parse_int=module._exact_integer)
try:
    issues, engine = module.validate_instance(request["instance"], request["schema"], request["engine"])
except module.SchemaError as exc:
    print(json.dumps({"schema_error": str(exc)}))
else:
    print(json.dumps({"issues": [issue.__dict__ for issue in issues], "engine": engine}))
"""


def _validate_in_child(instance: Any, schema: Any, engine: str) -> tuple[list[Issue], str]:
    """Validate in a child interpreter that is killed when the budget expires.

    The bound where no alarm can be delivered: the child's regex work cannot outlive the timeout,
    and a pattern that backtracks kills the child - never this process, which may be a service that
    only imported the validator. One child per instance, so the cost is a process start per
    manifest (about a second for the whole shipped sweep on Windows).
    """
    # _canonical, not json.dumps: a Decimal is not JSON-serializable, and json.dumps would raise
    # TypeError here - which the caller below would have caught, silently validating in this
    # process with no bound at all. _canonical writes a Decimal as the number token it came from,
    # and the child reads it back with this module's own parser.
    payload = _canonical({"instance": instance, "schema": schema, "engine": engine})
    try:
        finished = subprocess.run(
            [sys.executable, "-c", _CHILD_PROGRAM, str(Path(__file__).resolve())],
            input=payload, capture_output=True, text=True, check=False,
            timeout=_LIBRARY_PASS_BUDGET_SECONDS,
            env={**os.environ, _ISOLATION_ENV: "1"})
    except subprocess.TimeoutExpired:
        raise SchemaError(
            f"validating this instance did not finish within {_LIBRARY_PASS_BUDGET_SECONDS:g}s and the "
            "isolated validator was killed; a pattern in the schema backtracks on it") from None
    if finished.returncode != 0:
        raise SchemaError(f"the isolated validator exited {finished.returncode}: {finished.stderr.strip()[:400]}")
    answer = json.loads(finished.stdout)
    if "schema_error" in answer:
        raise SchemaError(answer["schema_error"])
    return [Issue(item["path"], item["message"]) for item in answer["issues"]], answer["engine"]


def validate_instance(instance: Any, schema: Any, engine: str = "auto") -> tuple[list[Issue], str]:
    """Return (issues, engine_used). engine: auto | jsonschema | builtin."""
    if engine not in ("auto", "jsonschema", "builtin"):
        raise ValueError(f"unknown engine {engine!r}")
    if not _alarm_deliverable() and not os.environ.get(_ISOLATION_ENV):
        # Nothing here can interrupt a match, so the whole pass moves into a child that can be
        # killed. Inside that child the marker is set and the parent's timeout is the bound.
        try:
            return _validate_in_child(instance, schema, engine)
        except (TypeError, ValueError, OSError):
            # Not JSON-serializable, or no interpreter to spawn: validate here rather than refuse,
            # and accept that this one pass has no bound. Reachable only off the main thread or on
            # a platform without setitimer, never in CI.
            pass
    use_library = engine == "jsonschema" or (engine == "auto" and jsonschema is not None)
    # One schema self-check for every engine - keyword shapes, $ref targets, regex portability and
    # the catastrophic-backtracking shape - so the library engine never accepts a schema that the
    # built-in engine (and the C# twin, JsonSchemaLite.WalkSchema) refuses: python-jsonschema would
    # happily run `\\Z`, `(?i)` or `^(a+)+$` and accepts `"enum": []`.
    checked = MiniValidator(schema)
    if use_library:
        if jsonschema is None:
            raise SchemaError("python package 'jsonschema' is not installed; use --engine builtin")
        # Decimal is a numbers.Number, so python-jsonschema calls it a "number", but its
        # "integer" check is isinstance(int) and would call 4.0 a non-integer where this engine
        # (and draft 2020-12) call it an integer. Teach the library the same two rules.
        type_checker = (jsonschema.Draft202012Validator.TYPE_CHECKER
                        .redefine("number", lambda _checker, instance: _matches_type(instance, "number"))
                        .redefine("integer", lambda _checker, instance: _matches_type(instance, "integer")))
        def _ascii_pattern(validator: Any, pattern: Any, instance: Any, _schema: Any) -> Any:
            # The library compiles patterns itself, with Python's Unicode defaults; this routes
            # them through the same compile the built-in engine uses - ASCII shorthand classes,
            # the portability refusals and the deadline - so all three paths judge one manifest
            # the same way.
            if not validator.is_type(instance, "string"):
                return
            compiled = checked._compile(pattern, "#")
            checked.charge("$")
            if not _bounded(f"matching {pattern!r}", "$", lambda: compiled.search(instance)):
                yield jsonschema.exceptions.ValidationError(f"{instance!r} does not match {pattern!r}")

        def _ascii_pattern_properties(validator: Any, pattern_properties: Any, instance: Any, _schema: Any) -> Any:
            if not validator.is_type(instance, "object"):
                return
            for pattern, subschema in pattern_properties.items():
                compiled = checked._compile(pattern, "#")
                for name, value in instance.items():
                    # Charged like the built-in engine's own loop: python-jsonschema counts nothing,
                    # so P patterns against N keys was P×N matches spent outside every budget, and
                    # the default (library) path could be held to the per-manifest deadline for
                    # every mapped manifest in the sweep.
                    checked.charge("$")
                    if _bounded(f"matching {pattern!r}", "$", lambda: compiled.search(name)):
                        yield from validator.descend(value, subschema, path=name, schema_path=pattern)

        def _ascii_additional_properties(validator: Any, additional: Any, instance: Any, schema_node: Any) -> Any:
            # The library decides which properties patternProperties already covers with its own
            # Unicode matcher, so overriding patternProperties alone left a property matched there
            # and validated nowhere. Coverage is decided by the same compile as everything else.
            if not validator.is_type(instance, "object"):
                return
            declared = schema_node.get("properties", {})
            patterns = schema_node.get("patternProperties", {})
            for name, value in instance.items():
                if name in declared:
                    continue
                covered = False
                for pattern in patterns:
                    compiled = checked._compile(pattern, "#")
                    checked.charge("$")   # the coverage matches are the same P×N work, charged too
                    if _bounded(f"matching {pattern!r}", "$", lambda: compiled.search(name)):
                        covered = True
                        break
                if covered:
                    continue
                if validator.is_type(additional, "object") or validator.is_type(additional, "boolean"):
                    if additional is False:
                        yield jsonschema.exceptions.ValidationError(
                            f"Additional properties are not allowed ('{name}' was unexpected)")
                    elif additional is not True:
                        yield from validator.descend(value, additional, path=name)

        validator_class = jsonschema.validators.extend(
            jsonschema.Draft202012Validator, type_checker=type_checker,
            validators={"pattern": _ascii_pattern, "patternProperties": _ascii_pattern_properties,
                        "additionalProperties": _ascii_additional_properties})
        try:
            validator_class.check_schema(schema)
        except jsonschema.exceptions.SchemaError as exc:
            raise SchemaError(f"schema is invalid: {exc.message}") from exc
        # Only the formats this module implements: the library's default checker also validates
        # "regex", "uri", "email" and more when their optional packages are present, and would then
        # refuse a manifest the built-in engine and the C# twin accept as an annotation.
        checker = jsonschema.FormatChecker(formats=[])
        # Register this module's date / date-time checks with the library engine: without the
        # optional rfc3339-validator package jsonschema's own FormatChecker silently accepts any
        # date-time, so the two engines would disagree on the shipped fabric contract.
        for format_name, check in _FORMATS.items():
            checker.checks(format_name)(lambda value, _check=check: not isinstance(value, str) or _check(value))
        validator = validator_class(schema, format_checker=checker)
        checked.reset_budget()   # the pass below gets the whole budget, not what the self-check left
        try:
            # python-jsonschema runs its own re matches and carries no timeout of its own, so the
            # whole pass goes under one deadline: the guarantee holds for both engines.
            with _match_deadline(_LIBRARY_PASS_BUDGET_SECONDS):
                raw_errors = list(validator.iter_errors(instance))
        except _MatchTimeout:
            raise SchemaError(
                f"validating this instance did not finish within {_LIBRARY_PASS_BUDGET_SECONDS:g}s and was "
                "abandoned; a pattern in the schema backtracks on it") from None
        except RecursionError as exc:  # "$ref": "#" and friends never descend into the instance
            raise SchemaError("schema nesting deeper than the engine allows - a $ref cycle that never descends into the instance") from exc
        except Exception as exc:  # a $ref that does not resolve surfaces as a referencing error
            if any(token in type(exc).__name__ for token in ("Referencing", "RefResolution", "Unresolvable")):
                raise SchemaError(f"schema $ref does not resolve: {exc}") from exc
            raise
        issues = [
            Issue(_format_json_path(error.absolute_path), message)
            for error, message in sorted(
                _descend_alternatives(raw_errors),
                key=lambda pair: (list(map(str, pair[0].absolute_path)), pair[1]))
        ]
        return issues, "jsonschema"
    return checked.iter_errors(instance), "builtin"


# --------------------------------------------------------------------------------------
# Repo wiring
# --------------------------------------------------------------------------------------

def _reject_constant(token: str) -> Any:
    # json.load accepts Python's NaN / Infinity / -Infinity spellings by default; they are not
    # JSON, and System.Text.Json (the hub's binder) refuses the file. Treat them as unreadable.
    raise ValueError(f"non-finite number token {token!r} is not JSON")


def _exact_number(token: str) -> Any:
    # Two rules in one place. A number too large for a double ("1e400") is refused: json maps it
    # to inf, inf is not a JSON number, and System.Text.Json - the hub's binder - refuses the same
    # token. Everything else is kept as a Decimal rather than a float, so the value the manifest
    # wrote survives parsing: 9007199254740993.0 and 9007199254740992.0 stay two numbers, and
    # 1e-324 stays distinct from zero.
    approximate = float(token)
    if not math.isfinite(approximate):
        raise ValueError(f"number token {token!r} is out of range for a JSON number (it reads as {approximate})")
    # The exponent as WRITTEN, before any normalization: the C# twin reads the same digits, so
    # neither engine has to reproduce the other's arithmetic to reach the same verdict. Checking a
    # normalized exponent instead made 1.1e-999999999999999999 and 10e-1000000000000000000 - one
    # scaled up by its fraction, one down by its trailing zero - land on opposite sides in the two.
    written = _EXPONENT_IN_TOKEN.search(token)
    if written is not None and _exponent_out_of_range(written.group(1)):
        raise ValueError(f"number token {token!r} is out of range for a JSON number "
                         f"(its exponent is past 1e{_MAX_EXPONENT}, which neither validation engine "
                         "can order exactly)")
    try:
        # An absurd exponent underflows the float check to 0.0 and then raises out of the Decimal
        # constructor ("1e-999999999999999999999999"); that is this manifest's verdict, not a
        # traceback through the CLI's --json output.
        value = decimal.Decimal(token)
    except decimal.DecimalException as exc:
        raise ValueError(f"number token {token!r} is out of range for a JSON number ({exc.__class__.__name__})") from exc
    return value


def _exact_integer(token: str) -> int:
    """An integer token, refused when no consumer could hold it.

    json's default parser builds a Python int of any size, so a 400-digit integer read fine here
    while ModelCatalog.TryLoad cannot bind it to a double and the C# engine reports it out of
    range - the required gate approving a catalog the hub cannot load. The same rule as
    _exact_number, applied to the tokens json routes past it.
    """
    if not math.isfinite(float(token)):
        raise ValueError(f"number token {token!r} is out of range for a JSON number "
                         f"(it reads as {float(token)})")
    return int(token)   # at most ~309 digits by the check above, so int() is bounded too


def load_json(path: Path, label: str) -> Any:
    try:
        with path.open(encoding="utf-8") as stream:
            return json.load(stream, parse_constant=_reject_constant, parse_float=_exact_number,
                             parse_int=_exact_integer)
    except FileNotFoundError as exc:
        raise ValueError(f"{label} not found: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"{label} is not valid JSON: {path} (line {exc.lineno}: {exc.msg})") from exc
    except ValueError as exc:  # _reject_constant
        raise ValueError(f"{label} is not valid JSON: {path} ({exc})") from exc


def _confined(repo_root: Path, relative: str, label: str) -> Path:
    """`repo_root / relative`, refused when it resolves - symbolic links included - outside the
    checkout: a manifests.json in a scanned tree is data and must not name files beyond that tree
    (validate_all.py sweeps untrusted HELIOS-shaped trees with this engine)."""
    root = repo_root.resolve()
    candidate = (root / relative).resolve()
    if candidate != root and root not in candidate.parents:
        raise ValueError(f"{label} '{relative}' resolves outside the checkout {root} and was refused")
    return candidate


def _ordinal_ignore_case(value: str) -> str:
    """Fold `value` the way .NET's OrdinalIgnoreCase does, so both engines judge one manifest alike.

    That comparer is a per-CHARACTER invariant uppercase (a simple mapping): it folds 'ς' onto 'Σ',
    where str.lower() keeps them apart, and leaves 'ß' alone, where str.upper() expands it to 'SS'.
    Uppercasing character by character and keeping any character whose uppercase is not a single
    character reproduces it.
    """
    return "".join(upper if len(upper := character.upper()) == 1 else character for character in value)


def _check_aihub_names(instance: Any) -> list[Issue]:
    """Provider keys and enabled CLI-agent names share ONE registry in the hub
    (AIHub.cs: `_byProvider[agent.Provider] = agent`, providers registered first): a CLI agent
    named like a provider, or two enabled agents with one name, silently replaces the earlier
    entry and every chain naming it reaches a different backend than configured. Compared
    case-insensitively, the way chain entries are looked up."""
    issues: list[Issue] = []
    if not isinstance(instance, dict):
        return issues
    owners: dict[str, str] = {}
    providers = instance.get("providers")
    if isinstance(providers, dict):
        for key, entry in providers.items():
            if isinstance(entry, dict) and entry.get("enabled") is False:
                continue  # ProviderFactory.CreateAll skips a disabled provider before registering it
            owners.setdefault(_ordinal_ignore_case(str(key)), f"providers.{key}")
    agents = instance.get("cliAgents")
    if isinstance(agents, list):
        for index, agent in enumerate(agents):
            if not isinstance(agent, dict) or agent.get("enabled") is False:
                continue  # a disabled entry is skipped by ProviderFactory.CreateAll before its name is read
            name = agent.get("name")
            if not isinstance(name, str):
                continue
            folded = _ordinal_ignore_case(name)
            owner = owners.get(folded)
            if owner is None:
                owners[folded] = f"cliAgents[{index}]"
            else:
                issues.append(Issue(f"$.cliAgents[{index}].name",
                                    f"'{name}' is already registered by {owner}; provider keys and CLI-agent names are one registry in the hub"))
    return issues


def _absolute_http_uri_problem(value: str) -> str | None:
    """Why `value` is not an absolute http(s) URI with a host and a valid port, or None.
    ProviderFactory hands baseUrl to `new Uri(...)`; the schema pattern excludes credentials and
    query data but cannot establish a host or a port, so `https://:80/x` and `https://host:bad/x`
    pass it and then fail on the first request."""
    try:
        parts = urlsplit(value)
        scheme, host = parts.scheme, parts.hostname
    except ValueError as exc:
        # urlsplit itself raises on a malformed bracketed host ("https://[bad]/"); that is an
        # invalid URI, so it is this manifest's verdict, never a traceback out of the sweep.
        return f"it does not parse as a URI ({exc})"
    if scheme not in ("http", "https"):
        return "the scheme must be http or https"
    if not host:
        return "the host is empty"
    try:
        parts.port
    except ValueError:
        return "the port is not a number in 0..65535"
    return None


def _check_aihub_base_urls(instance: Any) -> list[Issue]:
    issues: list[Issue] = []
    providers = instance.get("providers") if isinstance(instance, dict) else None
    if not isinstance(providers, dict):
        return issues
    for key, entry in providers.items():
        if not isinstance(entry, dict) or not isinstance(entry.get("baseUrl"), str):
            continue
        problem = _absolute_http_uri_problem(entry["baseUrl"])
        if problem is not None:
            issues.append(Issue(f"$.providers.{key}.baseUrl", f"{entry['baseUrl']!r} is not an absolute http(s) URI: {problem}"))
    return issues


def _chain_entries(instance: Any) -> list[tuple[str, list[Any]]]:
    """(json path, chain) for routing.defaultChain and every routing.taskRouting entry."""
    routing = instance.get("routing") if isinstance(instance, dict) else None
    if not isinstance(routing, dict):
        return []
    chains: list[tuple[str, list[Any]]] = []
    if isinstance(routing.get("defaultChain"), list):
        chains.append(("$.routing.defaultChain", routing["defaultChain"]))
    task_routing = routing.get("taskRouting")
    if isinstance(task_routing, dict):
        for key, chain in task_routing.items():
            if isinstance(chain, list):
                chains.append((f"$.routing.taskRouting.{key}", chain))
    return chains


def _check_aihub_chains(instance: Any) -> list[Issue]:
    """A chain entry that names nothing, or a chain of nothing but disabled entries, is a dead
    route that reads as configured: AIHub looks each entry up in the registry it built from
    providers + enabled CLI agents and simply skips what is not there (AIHub.cs), so a typo
    degrades the chain silently and an all-disabled chain fails every request it serves."""
    issues: list[Issue] = []
    if not isinstance(instance, dict):
        return issues
    known: set[str] = set()
    live: set[str] = set()
    providers = instance.get("providers")
    if isinstance(providers, dict):
        for key, entry in providers.items():
            known.add(_ordinal_ignore_case(str(key)))
            if not (isinstance(entry, dict) and entry.get("enabled") is False):
                live.add(_ordinal_ignore_case(str(key)))
    agents = instance.get("cliAgents")
    if isinstance(agents, list):
        for agent in agents:
            name = agent.get("name") if isinstance(agent, dict) else None
            if not isinstance(name, str):
                continue
            known.add(_ordinal_ignore_case(name))
            if agent.get("enabled") is not False:
                live.add(_ordinal_ignore_case(name))
    if not known:
        return issues  # nothing to resolve against; the schema's own required list reports that
    for path, chain in _chain_entries(instance):
        for index, entry in enumerate(chain):
            if isinstance(entry, str) and _ordinal_ignore_case(entry) not in known:
                issues.append(Issue(f"{path}[{index}]",
                                    f"'{entry}' names neither a provider key nor a CLI agent in this file; "
                                    "the hub skips an entry it cannot resolve"))
        if chain and not any(isinstance(entry, str) and _ordinal_ignore_case(entry) in live for entry in chain):
            issues.append(Issue(path, "no entry in this chain is an enabled provider or CLI agent; "
                                      "every request routed here would fail with no backend to try"))
    return issues


# The properties AIHubOptions and its nested records bind, by their canonical spelling. The
# binder is case-insensitive (AIHubOptions.Load sets PropertyNameCaseInsensitive), so a manifest
# carrying both `providers` and `Providers` binds them to one property in source order and the
# last one wins - silently replacing a section that validated.
# Metadata keys ($schema, $comment) are deliberately absent: nothing binds them, so a differently
# cased spelling of one cannot replace a section - it is just an unknown key, which this schema
# tolerates on purpose.
_AIHUB_KEYS: dict[str, tuple[str, ...]] = {
    "$": ("providers", "cliAgents", "routing", "learning"),
    "$.routing": ("defaultChain", "taskRouting"),
    "$.learning": ("enabled", "mode", "localPath", "tableEndpointEnv", "adaptiveRouting", "historyWindow"),
}
_AIHUB_PROVIDER_KEYS = ("type", "enabled", "model", "apiKeyEnv", "apiKeySecretName", "endpointEnv", "baseUrl")
_AIHUB_AGENT_KEYS = ("name", "enabled", "command", "argsTemplate", "model", "timeoutSeconds")


def _alias_issues(obj: Any, path: str, canonical: tuple[str, ...]) -> list[Issue]:
    """Keys that differ from a known property only by case: the binder folds them together."""
    if not isinstance(obj, dict):
        return []
    known = {_ordinal_ignore_case(name): name for name in canonical}
    issues: list[Issue] = []
    for key in obj:
        match = known.get(_ordinal_ignore_case(str(key)))
        if match is not None and str(key) != match:
            issues.append(Issue(f"{path}.{key}",
                                f"'{key}' differs from '{match}' only by case; the hub's binder folds them "
                                "together and the later one replaces the earlier"))
    return issues


def _check_aihub_keys(instance: Any) -> list[Issue]:
    issues: list[Issue] = []
    if not isinstance(instance, dict):
        return issues
    for path, canonical in _AIHUB_KEYS.items():
        node = instance if path == "$" else instance.get(path.split(".", 1)[1])
        issues.extend(_alias_issues(node, path, canonical))
    providers = instance.get("providers")
    if isinstance(providers, dict):
        # The provider map itself binds to a case-insensitive dictionary, so two keys differing
        # only by case are one provider with two spellings.
        seen: dict[str, str] = {}
        for key in providers:
            folded = _ordinal_ignore_case(str(key))
            if folded in seen:
                issues.append(Issue(f"$.providers.{key}",
                                    f"'{key}' repeats '{seen[folded]}'; provider keys are matched case-insensitively"))
            else:
                seen[folded] = str(key)
            issues.extend(_alias_issues(providers[key], f"$.providers.{key}", _AIHUB_PROVIDER_KEYS))
    agents = instance.get("cliAgents")
    if isinstance(agents, list):
        for index, agent in enumerate(agents):
            issues.extend(_alias_issues(agent, f"$.cliAgents[{index}]", _AIHUB_AGENT_KEYS))
    return issues


def _check_aihub(instance: Any) -> list[Issue]:
    return (_check_aihub_names(instance) + _check_aihub_base_urls(instance)
            + _check_aihub_chains(instance) + _check_aihub_keys(instance))


def _check_absorption_watchlist(instance: Any) -> list[Issue]:
    """A candidate's pull-request number is its identity: seed-absorption-tasks.ps1 derives the
    task id `absorb-pr-<n>` from it and reads the existing ids once, before the loop, so two
    entries with one number are enqueued twice under the same id in a single run."""
    candidates = instance.get("candidates") if isinstance(instance, dict) else instance
    if not isinstance(candidates, list):
        return []
    issues: list[Issue] = []
    seen: dict[int, int] = {}
    for index, candidate in enumerate(candidates):
        number = candidate.get("pr") if isinstance(candidate, dict) else None
        # 191 and 191.0 are one pull request: the identity check has to read a number the way the
        # schema's "integer" does, not the way Python spells it.
        if not isinstance(number, _NUMBER_TYPES) or isinstance(number, bool) or not _is_integer(number):
            continue
        first = seen.setdefault(int(number), index)
        if first != index:
            issues.append(Issue(f"$.candidates[{index}].pr",
                                f"pull request {int(number)} repeats entry {first}; both would seed the task "
                                "'absorb-pr-%d' in one run" % int(number)))
    return issues


def _check_github_milestones(instance: Any) -> list[Issue]:
    """apply-milestones.ps1 matches live milestones case-insensitively, so two entries differing
    only by case would both target one milestone: the second PATCH overwrites the first."""
    entries = instance.get("milestones") if isinstance(instance, dict) else instance
    prefix = "$.milestones" if isinstance(instance, dict) else "$"
    if not isinstance(entries, list):
        return []
    issues: list[Issue] = []
    seen: dict[str, int] = {}
    for index, entry in enumerate(entries):
        title = entry.get("title") if isinstance(entry, dict) else None
        if not isinstance(title, str):
            continue
        first = seen.setdefault(_ordinal_ignore_case(title), index)
        if first != index:
            issues.append(Issue(f"{prefix}[{index}].title",
                                f"'{title}' repeats entry {first} ('{entries[first].get('title')}'); "
                                "milestones are matched case-insensitively"))
    return issues


# What the fleet may attempt across ALL pools, not per pool. Every per-field ceiling is per pool,
# and `helios-fleet start` selects every pool by default: 100 pools of 64 workers each passed both
# validators and asked one host for 6,400 processes. scale-fleet.ps1 likewise sums each pool's
# burst lanes into ONE absolute `az vmss scale --new-capacity`, so the aggregate is what bills.
# Four times the 64-process ceiling start-fleet.ps1 enforces on a single pool, and twice the
# 256-lane ceiling one pool may request - far above the shipped topology (36 workers, 24 burst
# lanes across four pools) and far below a number that takes a host or an invoice down.
_MAX_FLEET_LOCAL_WORKERS = 256
_MAX_FLEET_BURST_LANES = 512


def _fleet_number(value: Any) -> int | None:
    """A capacity field as a whole number, or None when it is absent or not one.

    A whole number however it is spelled: PowerShell's [int] cast reads 64, 64.0 and 6.4e1 alike,
    and so does the C# twin's TryGetWholeNumber."""
    if isinstance(value, bool) or not isinstance(value, _NUMBER_TYPES) or not _is_integer(value):
        return None
    return int(value)


_FLEET_AUTOSCALING_KEYS = ("mode", "minLocalLanes", "maxLocalLanes", "maxBurstLanes",
                           "scaleUpQueueDepth", "scaleDownIdleSeconds", "burstTarget")


def _fleet_autoscaling(pool: dict[str, Any], defaults: dict[str, Any]) -> dict[str, Any] | None:
    """scale-fleet.ps1's Get-PoolAutoscaling: the pool's block merged over defaults', property by
    property. None when neither declares one - the reconciler then skips the pool entirely."""
    base = defaults.get("autoscaling")
    own = pool.get("autoscaling")
    if not isinstance(base, dict) and not isinstance(own, dict):
        return None
    base = base if isinstance(base, dict) else {}
    own = own if isinstance(own, dict) else {}
    merged: dict[str, Any] = {}
    for name in _FLEET_AUTOSCALING_KEYS:
        value = own.get(name, base.get(name))
        if value is not None:
            merged[name] = value
    return merged


def _fleet_lane_cap(pool: dict[str, Any], defaults: dict[str, Any]) -> int:
    """hermesFleet.maxConcurrentLanes for this pool, or 0 for "no declared cap". Both scripts read
    the pool's whole hermesFleet block or the defaults' - never a merge of the two."""
    hermes = pool.get("hermesFleet")
    if not isinstance(hermes, dict):
        hermes = defaults.get("hermesFleet")
    cap = _fleet_number(hermes.get("maxConcurrentLanes")) if isinstance(hermes, dict) else None
    return cap if cap is not None and cap > 0 else 0


def _check_fleet_capacity(instance: Any) -> list[Issue]:
    """The totals the fleet scripts act on, resolved the way they resolve them.

    start-fleet.ps1's Get-EffectivePoolSize: the pool's poolSize, else the defaults', else 1, then
    clamped to hermesFleet.maxConcurrentLanes. scale-fleet.ps1: the merged autoscaling block, where
    a `cloud` pool holds no local lanes at all, maxLocalLanes defaults to minLocalLanes (so a lone
    minimum IS the capacity), the lane cap clamps both, and the maximum is raised back to the
    minimum; burst lanes count only for a pool that may burst (hybrid or cloud).

    What the topology declares is what this bounds. `start-fleet.ps1 -PoolSize N` overrides every
    pool's size from the command line and the workspace profile lowers it; neither is in the file,
    and an operator typing a flag is making their own decision. This says what the manifest may ask
    for on its own.
    """
    if not isinstance(instance, dict):
        return []
    pools = instance.get("pools")
    if not isinstance(pools, list):
        return []
    defaults = instance.get("defaults") if isinstance(instance.get("defaults"), dict) else {}
    default_size = _fleet_number(defaults.get("poolSize"))
    workers = lanes = burst = 0
    for pool in pools:
        if not isinstance(pool, dict):
            continue
        cap = _fleet_lane_cap(pool, defaults)
        size = _fleet_number(pool.get("poolSize"))
        if size is None:
            size = default_size if default_size is not None else 1
        workers += min(size, cap) if cap else size

        autoscaling = _fleet_autoscaling(pool, defaults)
        if autoscaling is None:
            continue                       # no autoscaling block anywhere: the reconciler skips it
        mode = autoscaling.get("mode")
        mode = mode if isinstance(mode, str) else "local"
        minimum = _fleet_number(autoscaling.get("minLocalLanes"))
        minimum = 1 if minimum is None else minimum
        maximum = _fleet_number(autoscaling.get("maxLocalLanes"))
        maximum = minimum if maximum is None else maximum
        if mode == "cloud":
            minimum = maximum = 0
        if cap:
            maximum = min(maximum, cap)
            minimum = min(minimum, cap)
        lanes += max(maximum, minimum)
        if mode in ("hybrid", "cloud"):
            burst += _fleet_number(autoscaling.get("maxBurstLanes")) or 0
    issues: list[Issue] = []
    if workers > _MAX_FLEET_LOCAL_WORKERS:
        issues.append(Issue("$.pools",
                            f"{len(pools)} pools ask for {workers} worker processes together; "
                            f"start-fleet.ps1 selects every pool by default, and {_MAX_FLEET_LOCAL_WORKERS} "
                            "is the ceiling for one host"))
    if lanes > _MAX_FLEET_LOCAL_WORKERS:
        issues.append(Issue("$.pools",
                            f"maxLocalLanes totals {lanes} across the pools; scale-fleet.ps1 runs a "
                            f"local process per lane, and {_MAX_FLEET_LOCAL_WORKERS} is the ceiling "
                            "for one host"))
    if burst > _MAX_FLEET_BURST_LANES:
        issues.append(Issue("$.pools",
                            f"maxBurstLanes totals {burst} across the pools; scale-fleet.ps1 sums them "
                            f"into one 'az vmss scale --new-capacity', and {_MAX_FLEET_BURST_LANES} "
                            "is the ceiling for that request"))
    return issues


def _check_fleet_pools(instance: Any) -> list[Issue]:
    """A pool name is an identity: start-fleet.ps1 derives the assignee prefix and the Hermes board
    from it and scale-fleet.ps1 keys per-pool state by it, so two pools sharing a name share lanes
    and one silently absorbs the other's work."""
    pools = instance.get("pools") if isinstance(instance, dict) else None
    if not isinstance(pools, list):
        return []
    issues: list[Issue] = []
    seen: dict[str, int] = {}
    for index, pool in enumerate(pools):
        name = pool.get("name") if isinstance(pool, dict) else None
        if not isinstance(name, str):
            continue
        first = seen.setdefault(_ordinal_ignore_case(name), index)
        if first != index:
            issues.append(Issue(f"$.pools[{index}].name",
                                f"'{name}' repeats pool {first}; a pool name is its board, its assignee "
                                "prefix and its scaling key"))
    return issues + _check_fleet_capacity(instance)


def _check_github_labels(instance: Any) -> list[Issue]:
    """GitHub and apply-labels.ps1 identify labels case-insensitively; two entries whose names
    differ only by case would be POSTed twice or patched against each other on every run."""
    issues: list[Issue] = []
    if isinstance(instance, dict):
        entries, prefix = instance.get("labels"), "$.labels"
    else:
        entries, prefix = instance, "$"
    if not isinstance(entries, list):
        return issues
    seen: dict[str, int] = {}
    for index, entry in enumerate(entries):
        name = entry.get("name") if isinstance(entry, dict) else None
        if not isinstance(name, str):
            continue
        first = seen.setdefault(_ordinal_ignore_case(name), index)
        if first != index:
            issues.append(Issue(f"{prefix}[{index}].name",
                                f"'{name}' repeats entry {first} ('{entries[first].get('name')}'); GitHub matches label names case-insensitively"))
    return issues


def _check_model_catalog(instance: Any) -> list[Issue]:
    """A profile's identity is (provider, model), not the whole object.

    Two profiles repeating one pair but differing in price or context validate as distinct objects
    while the hub reads them as one model twice: ModelCatalog's context filter takes the FIRST
    match and preference ranking sees both, so the catalog states two facts for one model.
    scripts/build/validate-model-catalog.py already refuses the pair; this is the same rule where
    the shared engines - the CLI sweep and helios_config_validate - can see it.
    """
    models = instance.get("models") if isinstance(instance, dict) else None
    if not isinstance(models, list):
        return []
    issues: list[Issue] = []
    seen: dict[tuple[str, str], int] = {}
    for index, entry in enumerate(models):
        provider = entry.get("provider") if isinstance(entry, dict) else None
        model = entry.get("model") if isinstance(entry, dict) else None
        if not isinstance(provider, str) or not isinstance(model, str) or not provider or not model:
            continue
        first = seen.setdefault((provider, model), index)
        if first != index:
            issues.append(Issue(f"$.models[{index}]",
                                f"'{provider}/{model}' repeats entry {first}; a provider and model "
                                "name together identify one profile"))
    return issues


# The shapes scripts/validation/validate_helios_fabric_contract.py refuses anywhere in the Fabric
# contract. The contract records secret NAMES and references, never material, and a value like this
# in a free-text field (notes, receiptPath) is the one thing its schema cannot express.
_SECRET_SHAPES = (
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"xox[baprs]-[A-Za-z0-9-]{20,}"),
    re.compile(r"AIza[0-9A-Za-z_-]{35}"),
    re.compile(r"eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9._-]{12,}\.[A-Za-z0-9._-]{12,}"),
    re.compile(r"https?://[^/\s:@]+:[^/\s@]+@"),
)


def _iter_strings(value: Any, path: str = "$"):
    if isinstance(value, str):
        yield path, value
    elif isinstance(value, list):
        for index, item in enumerate(value):
            yield from _iter_strings(item, f"{path}[{index}]")
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from _iter_strings(item, f"{path}.{key}")


def _check_fabric_contract(instance: Any) -> list[Issue]:
    """No string in the contract may look like credential material.

    The authoritative validator scans every string; the shared engines are the path this repository
    advertises for authoring the contract, and without the rule they answer `valid: true` for a
    token pasted into a note. Names and references only - the repository's standing rule.
    """
    issues: list[Issue] = []
    for path, value in _iter_strings(instance):
        if any(shape.search(value) for shape in _SECRET_SHAPES):
            issues.append(Issue(path, "contains a secret-like value; the contract stores names and "
                                      "references, never the material itself"))
    return issues


def _normalize_manifest_key(path: str) -> str:
    key = path.replace("\\", "/")
    return key[2:] if key.startswith("./") else key


def _check_manifest_map(instance: Any) -> list[Issue]:
    """A manifest mapped twice would be validated against both schemas by the sweep while the
    single-file paths (find_mapping, the MCP tool) stop at the first entry: one file, two verdicts."""
    issues: list[Issue] = []
    mappings = instance.get("mappings") if isinstance(instance, dict) else None
    if not isinstance(mappings, list):
        return issues
    seen: dict[str, int] = {}
    for index, entry in enumerate(mappings):
        manifest = entry.get("manifest") if isinstance(entry, dict) else None
        if not isinstance(manifest, str):
            continue
        first = seen.setdefault(_normalize_manifest_key(manifest), index)
        if first != index:
            issues.append(Issue(f"$.mappings[{index}].manifest", f"'{manifest}' is already mapped by entry {first}; a manifest has exactly one schema"))
    return issues


# Rules a schema cannot express, keyed by the schema FILE this checkout ships. The $id inside a
# schema is editable data: keying on it meant that removing or mistyping one line silently
# switched every semantic rule off while ordinary validation still passed. The file name comes
# from the trusted manifest map, and the $id is only a fallback for a schema passed by --schema
# from outside the map. A test asserts every shipped schema still carries the $id its name implies.
_SEMANTIC_CHECKS: dict[str, Callable[[Any], list[Issue]]] = {
    "aihub.schema.json": _check_aihub,
    "github-labels.schema.json": _check_github_labels,
    "manifests.schema.json": _check_manifest_map,
    "github-milestones.schema.json": _check_github_milestones,
    "fleet-topology.schema.json": _check_fleet_pools,
    "absorption-pr-watchlist.schema.json": _check_absorption_watchlist,
    "model-catalog.schema.json": _check_model_catalog,
    "helios-fabric.v1.schema.json": _check_fabric_contract,
}


_SCHEMA_DIRECTORY = Path("config") / "schemas"


def _semantics_for(schema_path: Path, schema: Any, repo_root: Path = REPO_ROOT) -> Callable[[Any], list[Issue]] | None:
    """The semantic rules for a schema: by file name when it is one of this checkout's own schemas,
    otherwise by its $id. A file name alone is not identity - any tree can hold a file called
    aihub.schema.json - so the name only counts under config/schemas/ in this checkout."""
    try:
        shipped = schema_path.resolve().parent == (repo_root / _SCHEMA_DIRECTORY).resolve()
    except OSError:
        shipped = False
    if shipped:
        checks = _SEMANTIC_CHECKS.get(schema_path.name)
        if checks is not None:
            return checks
    identifier = schema.get("$id", "") if isinstance(schema, dict) else ""
    if not str(identifier).startswith("helios://config/schemas/"):
        return None
    return _SEMANTIC_CHECKS.get(str(identifier).rsplit("/", 1)[-1])


def load_mappings(repo_root: Path = REPO_ROOT) -> list[Mapping]:
    data = load_json(repo_root / MAPPING_FILE, "manifest map")
    if not isinstance(data, dict) or not isinstance(data.get("mappings"), list):
        raise ValueError(f"{MAPPING_FILE}: top level must be an object with a 'mappings' array")
    mappings: list[Mapping] = []
    seen: dict[str, int] = {}
    for index, entry in enumerate(data["mappings"]):
        if not isinstance(entry, dict) or not isinstance(entry.get("manifest"), str) \
                or not isinstance(entry.get("schema"), str):
            raise ValueError(f"{MAPPING_FILE}: mappings[{index}] must carry string 'manifest' and 'schema'")
        key = _normalize_manifest_key(entry["manifest"])
        if key in seen:
            raise ValueError(f"{MAPPING_FILE}: '{entry['manifest']}' is mapped twice (entries {seen[key]} and {index}); a manifest has exactly one schema")
        seen[key] = index
        mappings.append(Mapping(entry["manifest"], entry["schema"], str(entry.get("consumer", ""))))
    return mappings


def find_mapping(rel_path: str, mappings: list[Mapping]) -> Mapping | None:
    wanted = _normalize_manifest_key(rel_path)
    for mapping in mappings:
        if _normalize_manifest_key(mapping.manifest) == wanted:
            return mapping
    return None


def to_repo_relative(path: Path, repo_root: Path) -> str | None:
    """Repo-relative POSIX form of `path`, or None when it lies outside the repo."""
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except ValueError:
        return None


def validate_file(manifest_path: Path, schema_path: Path, engine: str = "auto",
                  repo_root: Path = REPO_ROOT) -> Result:
    schema = load_json(schema_path, "schema")
    label = to_repo_relative(manifest_path, repo_root) or str(manifest_path)
    schema_label = to_repo_relative(schema_path, repo_root) or str(schema_path)
    if not manifest_path.is_file():
        # A manifest that is not there is an input that could not be read (exit 2), not an
        # invalid manifest (exit 1): the caller named a path that does not exist.
        raise ValueError(f"manifest not found: {manifest_path}")
    try:
        instance = load_json(manifest_path, "manifest")
    except ValueError as exc:
        # A manifest that is not JSON is an invalid manifest, not a broken invocation.
        return Result(label, schema_label, False, [Issue("$", str(exc))], engine if engine != "auto" else "n/a")
    issues, used = validate_instance(instance, schema, engine)
    semantic = _semantics_for(schema_path, schema, repo_root)
    if semantic is not None:
        issues = issues + semantic(instance)
    return Result(label, schema_label, not issues, issues, used)


def validate_mapping(mapping: Mapping, engine: str = "auto", repo_root: Path = REPO_ROOT) -> Result:
    manifest_path = _confined(repo_root, mapping.manifest, "manifest")
    schema_path = _confined(repo_root, mapping.schema, "schema")
    return validate_file(manifest_path, schema_path, engine, repo_root)


def validate_all_mapped(engine: str = "auto", repo_root: Path = REPO_ROOT) -> list[Result]:
    return [validate_mapping(mapping, engine, repo_root) for mapping in load_mappings(repo_root)]


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------

def _resolve_manifest_argument(argument: str, repo_root: Path) -> Path:
    candidate = Path(argument)
    if candidate.is_absolute():
        return candidate
    if candidate.exists():
        return candidate.resolve()
    return repo_root / argument


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("manifests", nargs="*", help="manifest paths (repo-relative or absolute); default: every mapped manifest")
    parser.add_argument("--schema", help="validate the given manifests against this schema instead of the mapped one")
    parser.add_argument("--engine", choices=("auto", "jsonschema", "builtin"), default="auto")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    parser.add_argument("--list", action="store_true", help="print the manifest -> schema map and exit")
    parser.add_argument("--json", action="store_true", help="emit one JSON object on stdout")
    args = parser.parse_args(argv[1:])
    repo_root: Path = args.repo_root.resolve()

    def emit(payload: dict[str, Any], code: int) -> int:
        if args.json:
            print(json.dumps(payload, indent=2))
        return code

    try:
        mappings = load_mappings(repo_root)
        if args.list:
            if args.json:
                return emit({"mappings": [mapping.__dict__ for mapping in mappings]}, 0)
            for mapping in mappings:
                print(f"{mapping.manifest}  ->  {mapping.schema}")
            return 0

        results: list[Result] = []
        if args.manifests:
            for argument in args.manifests:
                manifest_path = _resolve_manifest_argument(argument, repo_root)
                if args.schema:
                    schema_path = _resolve_manifest_argument(args.schema, repo_root)
                else:
                    rel = to_repo_relative(manifest_path, repo_root)
                    mapping = find_mapping(rel, mappings) if rel else None
                    if mapping is None:
                        raise ValueError(
                            f"no schema is mapped for '{argument}' in {MAPPING_FILE}; add a mapping there "
                            "or pass --schema config/schemas/<name>.schema.json")
                    schema_path = repo_root / mapping.schema
                results.append(validate_file(manifest_path, schema_path, args.engine, repo_root))
        else:
            results = [validate_mapping(mapping, args.engine, repo_root) for mapping in mappings]
    except (ValueError, SchemaError, OSError) as exc:
        if args.json:
            print(json.dumps({"status": "error", "error": str(exc)}, indent=2))
        else:
            print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    invalid = [result for result in results if not result.valid]
    engine_used = results[0].engine if results else args.engine
    if args.json:
        return emit({
            "status": "failed" if invalid else "passed",
            "engine": engine_used,
            "results": [
                {
                    "manifest": result.manifest,
                    "schema": result.schema,
                    "valid": result.valid,
                    "errors": [issue.__dict__ for issue in result.issues],
                }
                for result in results
            ],
        }, 1 if invalid else 0)

    for result in results:
        if result.valid:
            print(f"OK    {result.manifest}  <-  {result.schema}")
        else:
            print(f"FAIL  {result.manifest}  <-  {result.schema}")
            for issue in result.issues:
                print(f"      {issue.path}: {issue.message}")
    print(f"config-schemas: {len(results) - len(invalid)} valid, {len(invalid)} invalid (engine: {engine_used})")
    return 1 if invalid else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
