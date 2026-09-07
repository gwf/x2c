#!/usr/bin/env python3
"""Read x2c sources well enough to describe their public surface.

Shared by `gen-module-catalog.py` and `gen-api-reference.py`. This module knows
only about source text; the authoritative types are in
`etc/header-symbols.xlisp` and are read by `x2c_symbols.py`.

`mask_non_code` is byte-length and newline preserving, so an offset into the
masked text indexes the raw text at the same position. `definitions` relies on
that to recover a doc comment from the raw text at a span the statement scanner
found in the masked text.
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
    "macro ", "@",
)
DOC_OPEN = "/**"
EXACT_IDENT = re.compile(
    r'\$\(\s*x2c\.ident\s+"([A-Za-z_][A-Za-z0-9_]*)"\s*\)'
)
MACRO_IMPORT = re.compile(
    r'\$\(\s*import\s+"([^"\n]+\.xmacro)"\s*\)'
)
KEYWORD_ALIAS = re.compile(
    r"\bkeyword\s+([A-Za-z_][A-Za-z0-9_]*)\s+"
    r"\$([A-Za-z_][A-Za-z0-9_.]*)\s*;"
)
DECORATOR_MACRO = re.compile(
    r"\bmacro\s+(?i:decorator)\s+\$([A-Za-z_][A-Za-z0-9_.]*)\s*\("
)
CHAR_LITERAL = re.compile(r"'(?:\\.|[^\\'\n])+'")
PRIVATE_PRAGMA = re.compile(
    r"(?m)^[ \t]*#[ \t]*pragma[ \t]+private\b"
)


@dataclass(frozen=True)
class Definition:
    """One non-static function definition found in a source file."""

    name: str            # source spelling, e.g. "Array.push"
    signature: str       # whitespace-normalized declarator text
    line: int            # 1-indexed line of the declarator
    doc: str | None      # normalized doc-comment body, or None


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


@dataclass(frozen=True)
class Declaration:
    """One public named typedef found in a source file."""

    name: str            # declared typedef name
    kind: str            # alias, struct, union, enum, or callback
    signature: str       # whitespace-normalized typedef, without `;`
    line: int            # 1-indexed line of the declaration
    doc: str | None      # normalized doc-comment body, or None


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


def blank_directives(masked: str) -> str:
    """Blank preprocessor lines and x2c imports.

    Length preserving, like `mask_non_code`: a directive line becomes spaces
    rather than disappearing, so offsets into the result still index the raw
    text. Shortening the text here silently shifts every reported line number.
    """
    lines: list[str] = []
    in_directive = False
    for line in masked.split("\n"):
        preprocessor = in_directive or line.lstrip().startswith("#")
        macro_import = bool(re.fullmatch(
            r"\s*\$\(\s*import\b.*\)\s*", line
        ))
        lines.append(" " * len(line)
                     if preprocessor or macro_import else line)
        in_directive = preprocessor and line.rstrip().endswith("\\")
    return "\n".join(lines)


def _macro_lisp_close(raw: str, opening: int) -> int | None:
    """Find a compile-time Lisp close without treating `'(` as a char."""
    depth = 0
    state = "code"
    index = opening
    while index < len(raw):
        char = raw[index]
        pair = raw[index:index + 2]
        if state == "code":
            if pair == "/*":
                state = "block-comment"
                index += 2
                continue
            if pair == "//":
                state = "line-comment"
                index += 2
                continue
            if char == '"':
                state = "string"
            elif char == "'" and index + 2 < len(raw) \
                    and raw[index + 2] == "'":
                index += 3
                continue
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    return index
        elif state == "string":
            if char == "\\":
                index += 2
                continue
            if char == '"':
                state = "code"
        elif state == "block-comment":
            if pair == "*/":
                state = "code"
                index += 2
                continue
        elif char == "\n":
            state = "code"
        index += 1
    return None


def blank_macro_lisp(raw: str, masked: str) -> str:
    """Blank balanced `$(...)` forms while preserving offsets."""
    result = list(masked)
    state = "code"
    index = 0
    while index + 1 < len(raw):
        char = raw[index]
        pair = raw[index:index + 2]
        if state == "block-comment":
            if pair == "*/":
                state = "code"
                index += 2
                continue
        elif state == "line-comment":
            if char == "\n":
                state = "code"
        elif state == "string":
            if char == "\\":
                index += 2
                continue
            if char == '"':
                state = "code"
        elif pair == "/*":
            state = "block-comment"
            index += 2
            continue
        elif pair == "//":
            state = "line-comment"
            index += 2
            continue
        elif char == '"':
            state = "string"
        elif char == "'":
            close_quote = raw.find("'", index + 1, index + 5)
            if close_quote >= 0:
                index = close_quote + 1
                continue
        elif pair == "$(":
            close = _macro_lisp_close(raw, index + 1)
            if close is None:
                break
            for blank in range(index, close + 1):
                if result[blank] != "\n":
                    result[blank] = " "
            index = close + 1
            continue
        index += 1
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
            if prefix.startswith("macro ") and body < len(masked) \
                    and masked[body] in "({[":
                pairs = {"(": ")", "{": "}", "[": "]"}
                close = _matching_delimiter(
                    masked, body, masked[body], pairs[masked[body]]
                )
                if close is None:
                    return spans
                start = close + 1
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


def _semicolon_statement_spans(masked: str) -> tuple[tuple[int, int], ...]:
    """Spans of top-level semicolon-terminated statements.

    Aggregate typedefs retain their body until the following semicolon. Other
    brace bodies reset the next statement start, just as `_statement_spans`
    does after a function definition.
    """
    spans: list[tuple[int, int]] = []
    depth = 0
    parens = 0
    brackets = 0
    start = 0
    aggregate = False
    for index, char in enumerate(masked):
        if depth == 0 and parens == 0 and brackets == 0 \
                and masked.startswith("typedef", index):
            before = masked[index - 1] if index else " "
            after = masked[index + len("typedef"):
                           index + len("typedef") + 1]
            if not (before.isalnum() or before == "_") \
                    and not (after.isalnum() or after == "_"):
                # Semicolon-free expression macros can sit between the
                # previous statement and a typedef. The typedef itself is the
                # only useful start for declaration and doc adjacency.
                start = index
        if char == "(" and depth == 0:
            parens += 1
            continue
        if char == ")" and depth == 0 and parens:
            parens -= 1
            continue
        if char == "[" and depth == 0:
            brackets += 1
            continue
        if char == "]" and depth == 0 and brackets:
            brackets -= 1
            continue
        if char == "{":
            if depth == 0:
                prefix = masked[start:index].lstrip()
                aggregate = bool(re.match(
                    r"typedef\s+(?:struct|union|enum)\b", prefix
                ))
            depth += 1
            continue
        if char == "}" and depth:
            depth -= 1
            if depth == 0 and not aggregate:
                start = index + 1
            continue
        if char == ";" and depth == 0 and parens == 0 and brackets == 0:
            spans.append((start, index))
            start = index + 1
            aggregate = False
    return tuple(spans)


def normalize_doc(body: str) -> str:
    """Normalize a doc-comment body to verbatim markdown.

    Strips an optional `*` gutter, then dedents. Never reflows: module and
    function prose in this tree contains lists that reflowing would destroy.
    """
    lines = body.splitlines()
    stripped: list[str] = []
    for line in lines:
        text = line.strip()
        if text == "*":
            stripped.append("")
            continue
        if text.startswith("* "):
            stripped.append(text[2:])
            continue
        stripped.append(line)
    # The first line shares its physical line with the `/**`, so its indent is
    # whatever followed the opener and says nothing about the block's gutter.
    # Dedent the remainder by their common indent, judged without it.
    if stripped:
        head, tail = stripped[0].strip(), stripped[1:]
        indents = [
            len(line) - len(line.lstrip())
            for line in tail
            if line.strip()
        ]
        if indents:
            cut = min(indents)
            tail = [line[cut:] if len(line) >= cut else line for line in tail]
        stripped = [head] + tail
    stripped = [line.rstrip() for line in stripped]
    while stripped and not stripped[0].strip():
        stripped.pop(0)
    while stripped and not stripped[-1].strip():
        stripped.pop()
    return "\n".join(stripped)


def _doc_before(raw: str, span_start: int, decl_start: int) -> str | None:
    """Return the `/**` doc comment ending just before decl_start, if any."""
    window = raw[span_start:decl_start]
    close = window.rfind("*/")
    if close < 0:
        return None
    open_at = window.rfind("/*", 0, close)
    if open_at < 0:
        return None
    opener = window[open_at:open_at + 3]
    if opener != DOC_OPEN:
        return None
    body = window[open_at + 3:close]
    if "/*" in body:
        return None
    between = window[close + 2:]
    if between.strip():
        return None
    if between.count("\n") > 1:
        # A blank line means the comment documents the section, not the
        # declaration below it.
        return None
    return normalize_doc(body)


def _foreign_alias_definitions(
    text: str, masked: str, include_static: bool
) -> tuple[Definition, ...]:
    """Checked foreign aliases are definitions without brace bodies."""
    marker = re.compile(r"\$x2c\.foreign\.alias")
    prefixes = NON_FUNCTION_PREFIXES
    if include_static:
        prefixes = tuple(p for p in prefixes if p != "static ")
    found: list[Definition] = []
    for match in marker.finditer(masked):
        cursor = match.end()
        while cursor < len(masked) and masked[cursor].isspace():
            cursor += 1
        if cursor >= len(masked) or masked[cursor] != "(":
            continue
        depth = 0
        while cursor < len(masked):
            if masked[cursor] == "(":
                depth += 1
            elif masked[cursor] == ")":
                depth -= 1
                if depth == 0:
                    cursor += 1
                    break
            cursor += 1
        while cursor < len(masked) and masked[cursor].isspace():
            cursor += 1
        semicolon = masked.find(";", cursor)
        if semicolon < 0:
            continue
        candidate_text = masked[cursor:semicolon]
        if "{" in candidate_text or "}" in candidate_text:
            continue
        candidate = " ".join(candidate_text.split())
        if not candidate or candidate.startswith(prefixes):
            continue
        name_match = NAME_PATTERN.search(candidate)
        if not name_match or name_match.group(1) in CONTROLS:
            continue
        boundary = max(
            masked.rfind(";", 0, match.start()),
            masked.rfind("}", 0, match.start()),
        )
        span_start = boundary + 1
        found.append(Definition(
            name=name_match.group(1),
            signature=candidate,
            line=text.count("\n", 0, cursor) + 1,
            doc=_doc_before(text, span_start, match.start()),
        ))
    return tuple(found)


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


def _comma_spans(text: str, start: int, end: int
                 ) -> tuple[tuple[int, int], ...]:
    """Split one argument list without splitting nested expressions."""
    spans: list[tuple[int, int]] = []
    item_start = start
    parens = brackets = braces = 0
    for index in range(start, end):
        char = text[index]
        if char == "(":
            parens += 1
        elif char == ")":
            parens -= 1
        elif char == "[":
            brackets += 1
        elif char == "]":
            brackets -= 1
        elif char == "{":
            braces += 1
        elif char == "}":
            braces -= 1
        elif char == "," and not (parens or brackets or braces):
            spans.append((item_start, index))
            item_start = index + 1
    spans.append((item_start, end))
    return tuple(spans)


def _unit_macro_definitions(
    text: str, masked: str, include_static: bool
) -> tuple[Definition, ...]:
    """Expand source-shaped declaration families for documentation.

    This is intentionally not a second macro evaluator. It recognizes unit
    macros whose body contains ordinary function definitions and substitutes
    their captured arguments textually. Signatures still get checked against
    the compiler's symbol artifact; this pass only keeps source-owned prose
    and declaration families visible to documentation tooling.
    """
    marker = re.compile(
        r"\bmacro\s+(?i:unit)\s+\$([A-Za-z_][A-Za-z0-9_.]*)\s*\("
    )
    found: list[Definition] = []
    for match in marker.finditer(masked):
        name = match.group(1)
        params_open = match.end() - 1
        params_close = _matching_delimiter(masked, params_open, "(", ")")
        if params_close is None:
            continue
        unit = re.match(
            r"\s*(?:using\s+[^=]+)?\s*=>\s*\{",
            masked[params_close + 1:]
        )
        if not unit:
            continue
        body_open = params_close + 1 + unit.end() - 1
        body_close = _matching_delimiter(masked, body_open, "{", "}")
        if body_close is None:
            continue

        holes: list[str] = []
        for first, last in _comma_spans(
            masked, params_open + 1, params_close
        ):
            names = re.findall(
                r"\$([A-Za-z_][A-Za-z0-9_]*)", masked[first:last]
            )
            if not names:
                holes = []
                break
            holes.append(names[-1])
        if not holes:
            continue

        invocation = re.compile(
            rf"\${re.escape(name)}\s*\("
        )
        for call in invocation.finditer(masked):
            if match.start() <= call.start() <= body_close:
                continue
            args_open = call.end() - 1
            args_close = _matching_delimiter(masked, args_open, "(", ")")
            if args_close is None:
                continue
            spans = _comma_spans(masked, args_open + 1, args_close)
            if len(spans) != len(holes):
                continue
            arguments = [
                text[first:last].strip() for first, last in spans
            ]
            expanded = text[body_open + 1:body_close]
            for hole, argument in zip(holes, arguments):
                expanded = re.sub(
                    rf"\${re.escape(hole)}\b", argument, expanded
                )
            # Exact identifiers are source-shaped names, not arbitrary Lisp.
            # Materialize the literal form so public parameter spellings in a
            # macro definition remain checkable against the symbol artifact.
            expanded = EXACT_IDENT.sub(r"\1", expanded)
            line = text.count("\n", 0, call.start()) + 1
            call_doc = _doc_before(text, 0, call.start())
            for definition in definitions(expanded, include_static):
                found.append(Definition(
                    name=definition.name,
                    signature=definition.signature,
                    line=line,
                    doc=definition.doc or call_doc,
                ))
    return tuple(found)


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


def definitions(text: str, include_static: bool = False
                ) -> tuple[Definition, ...]:
    """Every function definition, with its doc comment.

    Static definitions are excluded by default because they are not API. Pass
    include_static to account for them anyway: the symbol artifact records
    statics too, so a reverse check against it needs the full set or it
    mistakes a static method such as `Lisp._initialize` for a scanner gap.
    """
    without_lisp = blank_macro_lisp(text, text)
    masked = blank_directives(mask_non_code(without_lisp))
    found: list[Definition] = []
    seen: set[str] = set()
    for span in function_spans(masked, include_static):
        name = span.name
        if name in seen:
            continue
        seen.add(name)
        found.append(Definition(
            name=name,
            signature=" ".join(
                masked[span.declaration_start:span.body_marker].split()
            ),
            line=text.count("\n", 0, span.declaration_start) + 1,
            doc=_doc_before(text, span.start, span.doc_anchor),
        ))
    found.extend(_foreign_alias_definitions(
        text, masked, include_static
    ))
    for definition in _unit_macro_definitions(
        text, masked, include_static
    ):
        if definition.name in seen:
            continue
        seen.add(definition.name)
        found.append(definition)
    found.sort(key=lambda definition: definition.line)
    return tuple(found)


def _imported_macro_texts(path: pathlib.Path, text: str,
                          loaded: set[pathlib.Path]
                          ) -> tuple[str, ...]:
    """Load imported .xmacro sources once, in dependency order."""
    sources: list[str] = []
    for match in MACRO_IMPORT.finditer(text):
        imported = (path.parent / match.group(1)).resolve()
        if imported in loaded or not imported.is_file():
            continue
        loaded.add(imported)
        imported_text = imported.read_text(encoding="utf-8")
        sources.extend(_imported_macro_texts(
            imported, imported_text, loaded
        ))
        sources.append(imported_text)
    return tuple(sources)


def definitions_for_path(path: pathlib.Path, include_static: bool = False
                         ) -> tuple[Definition, ...]:
    """Definitions in one source, including imported unit-macro output."""
    path = path.resolve()
    text = path.read_text(encoding="utf-8")
    imported = _imported_macro_texts(path, text, set())
    if not imported:
        return definitions(text, include_static)
    # The synthetic semicolon keeps a trailing top-level Lisp or expression
    # macro in an imported file from swallowing the source's first span.
    prefix = "\n".join(imported) + "\n;\n"
    prefix_lines = prefix.count("\n")
    found: list[Definition] = []
    for definition in definitions(prefix + text, include_static):
        if definition.line <= prefix_lines:
            continue
        found.append(Definition(
            name=definition.name,
            signature=definition.signature,
            line=definition.line - prefix_lines,
            doc=definition.doc,
        ))
    return tuple(found)


def _declaration_name(signature: str) -> tuple[str, str] | None:
    """Return one typedef's name and kind from a normalized signature."""
    callback = re.search(
        r"\(\s*\*\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)\s*\(",
        signature,
    )
    if callback:
        return callback.group(1), "callback"

    aggregate = re.match(r"typedef\s+(struct|union|enum)\b", signature)
    declarator = signature
    if aggregate and "}" in declarator:
        declarator = declarator.rsplit("}", 1)[1]
    elif "[" in declarator:
        declarator = declarator.split("[", 1)[0]
    names = re.findall(r"[A-Za-z_][A-Za-z0-9_]*", declarator)
    if not names:
        return None
    return names[-1], aggregate.group(1) if aggregate else "alias"


def public_declarations(text: str) -> tuple[Declaration, ...]:
    """Public named typedefs before the first `#pragma private`.

    The result covers ordinary aliases, aggregate typedefs, and function
    pointer callbacks. Compile-time `x2c_var_abi_*` char-array assertions are
    deliberately not types in the public API.
    """
    code = mask_non_code(text)
    private = PRIVATE_PRAGMA.search(code)
    if private:
        text = text[:private.start()]
    without_lisp = blank_macro_lisp(text, text)
    masked = blank_directives(mask_non_code(without_lisp))
    found: list[Declaration] = []
    for start, semicolon in _semicolon_statement_spans(masked):
        statement = masked[start:semicolon]
        typedef = re.search(r"\btypedef\b", statement)
        if not typedef:
            continue
        decl_start = start + typedef.start()
        signature = " ".join(masked[decl_start:semicolon].split())
        if re.match(
            r"typedef\s+char\s+x2c_var_abi_[A-Za-z0-9_]*\s*\[",
            signature,
        ):
            continue
        identified = _declaration_name(signature)
        if identified is None:
            continue
        name, kind = identified
        found.append(Declaration(
            name=name,
            kind=kind,
            signature=signature,
            line=text.count("\n", 0, decl_start) + 1,
            doc=_doc_before(text, 0, decl_start),
        ))
    return tuple(found)


def public_declarations_for_path(
    path: pathlib.Path,
) -> tuple[Declaration, ...]:
    """Public named typedefs written directly in one source file."""
    return public_declarations(path.read_text(encoding="utf-8"))


def public_functions(text: str) -> tuple[str, ...]:
    """Function names in source order."""
    return tuple(d.name for d in definitions(text))


def public_functions_for_path(path: pathlib.Path) -> tuple[str, ...]:
    """Names from one source and its imported unit macros."""
    return tuple(d.name for d in definitions_for_path(path))


def module_paragraphs(text: str) -> tuple[str, ...]:
    """Paragraphs of the module's leading block comment.

    Tolerates `#pragma once` and other directives before the comment, which
    seven runtime modules put first.
    """
    prefix = re.match(r"(?:\s*#[^\n]*\n)*\s*", text)
    offset = prefix.end() if prefix else 0
    if not text[offset:].startswith("/*"):
        return ()
    close = text.find("*/", offset)
    if close < 0:
        return ()
    opener = 3 if text[offset:offset + 3] == DOC_OPEN else 2
    body = normalize_doc(text[offset + opener:close])
    paragraphs = [p.strip("\n") for p in re.split(r"\n\s*\n", body)]
    return tuple(p for p in paragraphs if p.strip())


def module_summary(text: str, path: pathlib.Path) -> str:
    """The catalog's one-line summary for a module."""
    paragraphs = module_paragraphs(text)
    if not paragraphs:
        return f"Current source module `{path.name}`."
    first = " ".join(paragraphs[0].split())
    marker = " -- "
    if marker in first:
        first = first.split(marker, 1)[1]
    return first.rstrip(". ") + "."


def module_prose(text: str) -> tuple[str, ...]:
    """Module-comment paragraphs after the title and the copyright notice."""
    paragraphs = module_paragraphs(text)
    return tuple(
        p for p in paragraphs[1:] if not p.lstrip().startswith("Copyright")
    )


def split_signature(signature: str) -> tuple[str, str, tuple[str, ...]]:
    """Split a declarator into (return text, name, parameter texts)."""
    match = NAME_PATTERN.search(signature)
    if not match:
        raise ValueError(f"no callable name in {signature!r}")
    name = match.group(1)
    ret = signature[:match.start(1)].strip()
    for qualifier in ("inline ", "extern "):
        while ret.startswith(qualifier):
            ret = ret[len(qualifier):].strip()
    open_paren = signature.index("(", match.end(1) - 1)
    depth = 0
    close = None
    for index in range(open_paren, len(signature)):
        if signature[index] == "(":
            depth += 1
        elif signature[index] == ")":
            depth -= 1
            if depth == 0:
                close = index
                break
    if close is None:
        raise ValueError(f"unbalanced parameters in {signature!r}")
    inner = signature[open_paren + 1:close].strip()
    params: list[str] = []
    if inner and inner != "void":
        depth = 0
        current: list[str] = []
        for char in inner:
            if char == "," and depth == 0:
                params.append("".join(current).strip())
                current = []
                continue
            if char in "([":
                depth += 1
            elif char in ")]":
                depth -= 1
            current.append(char)
        params.append("".join(current).strip())
    elif inner == "void":
        params.append("void")
    return ret, name, tuple(params)
