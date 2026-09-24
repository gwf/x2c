#!/usr/bin/env python3
"""Mask and scan x2c source for the remaining Python analyzers.

`audit-source-bloat.py`, the redundant-validation analyzer, and the
overengineering analyzer import `function_spans` and `mask_non_code`.
Documentation reads the compiler's `--dump-definitions` projection instead
(`tools/definitions.x`); this module is removed when those analyzers move to
compiler-backed tools.

`mask_non_code` is byte-length and newline preserving, so an offset into the
masked text indexes the raw text at the same position.
"""

from __future__ import annotations

import pathlib
import re
from dataclasses import dataclass


NAME_PATTERN = re.compile(
    r"([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)\s*\("
)
CONTROLS = {"if", "for", "while", "switch", "catch", "match"}
NON_FUNCTION_PREFIXES = (
    "static ", "typedef ", "struct ", "union ", "enum ", "protocol ",
    "macro ", "class ", "@",
)
KEYWORD_ALIAS = re.compile(
    r"\bkeyword\s+([A-Za-z_][A-Za-z0-9_]*)\s+"
    r"\$([A-Za-z_][A-Za-z0-9_.]*)\s*;"
)
DECORATOR_MACRO = re.compile(
    r"\bmacro\s+(?i:decorator)\s+\$([A-Za-z_][A-Za-z0-9_.]*)\s*\("
)
CHAR_LITERAL = re.compile(r"'(?:\\.|[^\\'\n])+'")


@dataclass(frozen=True)
class FunctionSpan:
    """One source function definition and its body offsets."""

    name: str
    start: int
    declaration_start: int
    doc_anchor: int
    body_marker: int
    body_start: int
    end: int
    expression_body: bool


def mask_non_code(text: str) -> str:
    """Mask comments and literals while preserving newlines and braces."""
    result: list[str] = []
    state = "code"
    i = 0
    while i < len(text):
        char = text[i]
        pair = text[i : i + 2]
        if state == "code":
            if pair == "/*":
                result.extend("  ")
                state = "block-comment"
                i += 2
                continue
            if pair == "//":
                result.extend("  ")
                state = "line-comment"
                i += 2
                continue
            if char == '"':
                result.append(" ")
                state = "string"
                i += 1
                continue
            if char == "'" and CHAR_LITERAL.match(text, i):
                result.append(" ")
                state = "char"
                i += 1
                continue
            result.append(char)
        elif state == "block-comment":
            if pair == "*/":
                result.extend("  ")
                state = "code"
                i += 2
                continue
            result.append("\n" if char == "\n" else " ")
        elif state == "line-comment":
            if char == "\n":
                result.append("\n")
                state = "code"
            else:
                result.append(" ")
        else:
            if char == "\\" and i + 1 < len(text):
                result.extend("  ")
                i += 2
                continue
            if (state == "string" and char == '"') or (
                state == "char" and char == "'"
            ):
                result.append(" ")
                state = "code"
            else:
                result.append("\n" if char == "\n" else " ")
        i += 1
    return "".join(result)


def _statement_spans(masked: str) -> list[tuple[int, int]]:
    """Spans of top-level function-shaped statements as (start, body marker).

    The span starts after the previous `;` or `}`, so it still contains any
    comment written above the declarator. That is what makes doc-comment
    recovery possible without a second scan. Arrow expressions are skipped
    through their balanced terminating semicolon so braces inside literals or
    lambdas cannot look like following definitions.
    """
    spans: list[tuple[int, int]] = []
    depth = 0
    parens = 0
    brackets = 0
    start = 0
    index = 0
    while index < len(masked):
        char = masked[index]
        if depth:
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    # Reset the span, or the next declarator inherits this
                    # function body and the scanner reports phantom names.
                    start = index + 1
            index += 1
            continue
        if char == "(":
            parens += 1
            index += 1
            continue
        if char == ")" and parens:
            parens -= 1
            index += 1
            continue
        if char == "[":
            brackets += 1
            index += 1
            continue
        if char == "]" and brackets:
            brackets -= 1
            index += 1
            continue
        if char == ";" and not parens and not brackets:
            start = index + 1
            index += 1
            continue
        if char == "{" and not parens and not brackets:
            prefix = masked[start:index].lstrip()
            if prefix.startswith("macro "):
                close = _matching_delimiter(masked, index, "{", "}")
                if close is None:
                    return spans
                start = close + 1
                index = start
                continue
            spans.append((start, index))
            depth = 1
            index += 1
            continue
        if char == "=" and not parens and not brackets:
            arrow = index + 1
            while arrow < len(masked) and masked[arrow].isspace():
                arrow += 1
            if arrow >= len(masked) or masked[arrow] != ">":
                index += 1
                continue
            prefix = masked[start:index].lstrip()
            body = arrow + 1
            while body < len(masked) and masked[body].isspace():
                body += 1
            if prefix.startswith("macro "):
                end = _macro_arrow_body_end(masked, body)
                if end is None:
                    return spans
                start = end
                index = start
                continue
            end = _expression_semicolon(masked, body)
            if end is None:
                return spans
            spans.append((start, index))
            start = end + 1
            index = start
            continue
        index += 1
    return spans


def _macro_arrow_body_end(masked: str, start: int) -> int | None:
    """Return the end after either spelling of an arrow macro body.

    Legacy expression bodies are one balanced parenthesized form without a
    semicolon. Canonical expression bodies end at a semicolon, including when
    their first operand is parenthesized. Braced bodies are balanced in both
    the legacy `=> {}` spelling and the compatibility scanner.
    """
    if start >= len(masked):
        return None
    if masked[start] == "{":
        close = _matching_delimiter(masked, start, "{", "}")
        return None if close is None else close + 1
    if masked[start] != "(":
        semicolon = _expression_semicolon(masked, start)
        return None if semicolon is None else semicolon + 1

    close = _matching_delimiter(masked, start, "(", ")")
    if close is None:
        return None
    following = close + 1
    while following < len(masked) and masked[following].isspace():
        following += 1
    if following < len(masked) and masked[following] == ";":
        return following + 1
    if following < len(masked) and (
        masked[following] in "([.?,:+-*/%&|^<>=!@" or
        re.match(r"(?:in|is)\b", masked[following:])
    ):
        semicolon = _expression_semicolon(masked, start)
        return None if semicolon is None else semicolon + 1
    return close + 1


def _expression_semicolon(masked: str, start: int) -> int | None:
    """Return the first semicolon outside balanced expression delimiters."""
    parens = brackets = braces = 0
    for index in range(start, len(masked)):
        char = masked[index]
        if char == "(":
            parens += 1
        elif char == ")" and parens:
            parens -= 1
        elif char == "[":
            brackets += 1
        elif char == "]" and brackets:
            brackets -= 1
        elif char == "{":
            braces += 1
        elif char == "}" and braces:
            braces -= 1
        elif char == ";" and not (parens or brackets or braces):
            return index
    return None


def _has_top_level_assignment(text: str) -> bool:
    """Whether declarator text contains an initializer assignment."""
    parens = brackets = braces = 0
    for char in text:
        if char == "(":
            parens += 1
        elif char == ")" and parens:
            parens -= 1
        elif char == "[":
            brackets += 1
        elif char == "]" and brackets:
            brackets -= 1
        elif char == "{":
            braces += 1
        elif char == "}" and braces:
            braces -= 1
        elif char == "=" and not (parens or brackets or braces):
            return True
    return False


def _matching_delimiter(text: str, start: int, opening: str,
                        closing: str) -> int | None:
    """Return the matching delimiter, ignoring already-masked literals."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] == opening:
            depth += 1
        elif text[index] == closing:
            depth -= 1
            if depth == 0:
                return index
    return None


def _decorated_target_start(masked: str, start: int, end: int
                            ) -> tuple[int, int]:
    """Return the target declarator and documentation-anchor offsets.

    A decorator application is source adjacency rather than part of the
    preserved function signature. Peel stacked applications without loading
    imports or evaluating their bodies, matching the compiler's shallow
    declaration collection boundary.
    """
    cursor = start
    while cursor < end and masked[cursor].isspace():
        cursor += 1
    doc_anchor = cursor
    decorators = {
        match.group(1)
        for match in DECORATOR_MACRO.finditer(masked, 0, start)
    }
    aliases = {
        match.group(1)
        for match in KEYWORD_ALIAS.finditer(masked, 0, start)
        if match.group(2) in decorators
    }
    while cursor < end:
        if masked[cursor] == "$":
            application = re.match(
                r"\$[A-Za-z_][A-Za-z0-9_.]*\s*\(", masked[cursor:end]
            )
            if not application:
                break
            opening = cursor + application.end() - 1
            closing = _matching_delimiter(masked, opening, "(", ")")
            if closing is None or closing >= end:
                break
            cursor = closing + 1
        else:
            application = re.match(
                r"([A-Za-z_][A-Za-z0-9_]*)\b", masked[cursor:end]
            )
            if not application or application.group(1) not in aliases:
                break
            cursor += application.end()
            while cursor < end and masked[cursor].isspace():
                cursor += 1
            if cursor < end and masked[cursor] == "(":
                closing = _matching_delimiter(masked, cursor, "(", ")")
                if closing is None or closing >= end:
                    break
                cursor = closing + 1
        while cursor < end and masked[cursor].isspace():
            cursor += 1
    return cursor, doc_anchor


def function_spans(masked: str, include_static: bool = False
                   ) -> tuple[FunctionSpan, ...]:
    """Return top-level function definitions in already-masked source."""
    prefixes = NON_FUNCTION_PREFIXES
    if include_static:
        prefixes = tuple(p for p in prefixes if p != "static ")
    found: list[FunctionSpan] = []
    for start, marker in _statement_spans(masked):
        decl_start, doc_anchor = _decorated_target_start(
            masked, start, marker
        )
        candidate = " ".join(masked[decl_start:marker].split())
        if not candidate or candidate.startswith(prefixes):
            continue
        if _has_top_level_assignment(masked[decl_start:marker]):
            continue
        if include_static and candidate.startswith("static "):
            body = candidate[len("static "):].lstrip()
            if body.startswith(("typedef ", "struct ", "union ", "enum ")):
                continue
        match = NAME_PATTERN.search(candidate)
        if not match or match.group(1) in CONTROLS:
            continue
        expression_body = masked[marker] == "="
        if expression_body:
            arrow = marker + 1
            while arrow < len(masked) and masked[arrow].isspace():
                arrow += 1
            if arrow >= len(masked) or masked[arrow] != ">":
                continue
            body_start = arrow + 1
            semicolon = _expression_semicolon(masked, body_start)
            if semicolon is None:
                continue
            end = semicolon + 1
        else:
            close = _matching_delimiter(masked, marker, "{", "}")
            if close is None:
                continue
            body_start = marker + 1
            end = close + 1
        found.append(FunctionSpan(
            name=match.group(1),
            start=start,
            declaration_start=decl_start,
            doc_anchor=doc_anchor,
            body_marker=marker,
            body_start=body_start,
            end=end,
            expression_body=expression_body,
        ))
    return tuple(found)
