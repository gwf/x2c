#!/usr/bin/env python3
"""Report compact x2c source-style findings without rewriting source."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Finding:
    kind: str
    category: str
    line: int
    message: str


def _mask(text: str) -> str:
    """Mask comments and quoted literals while preserving layout."""
    out = list(text)
    i = 0
    state = "code"
    quote = ""
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if ch == "/" and nxt == "/":
                out[i] = out[i + 1] = " "
                state = "line"
                i += 2
                continue
            if ch == "/" and nxt == "*":
                out[i] = out[i + 1] = " "
                state = "block"
                i += 2
                continue
            if ch in "\"'":
                quote = ch
                out[i] = " "
                state = "quote"
                i += 1
                continue
        elif state == "line":
            if ch == "\n":
                state = "code"
            else:
                out[i] = " "
        elif state == "block":
            if ch == "*" and nxt == "/":
                out[i] = out[i + 1] = " "
                state = "code"
                i += 2
                continue
            if ch != "\n":
                out[i] = " "
        else:
            if ch == "\\" and nxt:
                out[i] = " "
                if nxt != "\n":
                    out[i + 1] = " "
                i += 2
                continue
            if ch == quote:
                state = "code"
            if ch != "\n":
                out[i] = " "
        i += 1
    return "".join(out)


def _line_offsets(text: str) -> list[int]:
    offsets = [0]
    offsets.extend(i + 1 for i, ch in enumerate(text) if ch == "\n")
    return offsets


def _line_at(offsets: list[int], position: int) -> int:
    lo, hi = 0, len(offsets)
    while lo + 1 < hi:
        mid = (lo + hi) // 2
        if offsets[mid] <= position:
            lo = mid
        else:
            hi = mid
    return lo + 1


def _pairs(masked: str, opener: str, closer: str) -> list[tuple[int, int]]:
    stack: list[int] = []
    pairs: list[tuple[int, int]] = []
    for i, ch in enumerate(masked):
        if ch == opener:
            stack.append(i)
        elif ch == closer and stack:
            pairs.append((stack.pop(), i))
    return pairs


def _call_name(masked: str, opening: int) -> str | None:
    end = opening
    while end and masked[end - 1].isspace():
        end -= 1
    start = end
    while start and (masked[start - 1].isalnum() or
                     masked[start - 1] in "_."):
        start -= 1
    name = masked[start:end]
    if not re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?", name):
        return None
    if name in {"if", "for", "foreach", "while", "switch", "sizeof", "match"}:
        return None
    if start and masked[start - 1] in "$%@":
        return None
    return name


def _top_level_argument_is_multiline(
    text: str, masked: str, opening: int, closing: int, offsets: list[int]
) -> bool:
    cuts = [opening]
    round_depth = square_depth = brace_depth = 0
    for i in range(opening + 1, closing):
        ch = masked[i]
        if ch == "(": round_depth += 1
        elif ch == ")": round_depth -= 1
        elif ch == "[": square_depth += 1
        elif ch == "]": square_depth -= 1
        elif ch == "{": brace_depth += 1
        elif ch == "}": brace_depth -= 1
        elif ch == "," and not (round_depth or square_depth or brace_depth):
            cuts.append(i)
    cuts.append(closing)
    for left, end in zip(cuts, cuts[1:]):
        start = left + 1
        while start < end and text[start].isspace(): start += 1
        while end > start and (text[end - 1].isspace() or text[end - 1] == ","):
            end -= 1
        if start < end and _line_at(offsets, start) != _line_at(offsets, end - 1):
            return True
    return False


def _looks_like_declaration_prefix(prefix: str) -> bool:
    clean = prefix.strip()
    if not clean or any(ch in clean for ch in "=;{}[]"):
        return False
    first = clean.split()[0]
    if first in {"return", "protocol", "typedef", "defer", "case", "else"}:
        return False
    return bool(re.fullmatch(
        r"(?:(?:static|inline|extern|const|unsigned|signed|long|short|struct)\s+)*"
        r"[A-Za-z_]\w*(?:\s*[*&]\s*|\s+)+[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)?",
        clean,
    ))


def _line_has_comment(original: str) -> bool:
    return "//" in original or "/*" in original or "*/" in original


def analyze_text(path: str, text: str) -> list[Finding]:
    masked = _mask(text)
    lines = text.splitlines()
    code_lines = masked.splitlines()
    offsets = _line_offsets(masked)
    findings: list[Finding] = []

    def add(kind: str, category: str, line: int, message: str) -> None:
        findings.append(Finding(kind, category, line, message))

    # Mechanical whitespace and width.
    blank = False
    for number, (line, code) in enumerate(zip(lines, code_lines), 1):
        if "\t" in line: add("violation", "tab", number, "tab character")
        if line != line.rstrip():
            add("violation", "trailing_whitespace", number, "trailing whitespace")
        if not line.strip():
            if blank:
                add("violation", "blank_line_stack", number, "consecutive blank line")
            blank = True
        else:
            blank = False
        for match in re.finditer(r"[|&+*/=-] {2,}\S", line):
            if code[match.start()] != " " and code[match.end() - 1] != " ":
                add("violation", "operator_spacing", number,
                    "doubled operator spacing")
                break
        if len(line) > 79:
            stripped = line.strip()
            table = (stripped.startswith("{") and
                     re.search(r"}[,;]?\s*(?://.*)?$", stripped) and
                     stripped.count(",") >= 2 and ("\"" in line or "<" in line))
            if table:
                add("candidate", "over_width_table_row", number,
                    "verify that indivisible literal fields require this stable row")
            elif "\"" in line or "%\"" in line:
                add("candidate", "over_width_literal", number,
                    "verify that preserving observable literal text requires this width")
            else:
                add("violation", "over_width", number, f"{len(line)} columns")

    parens = _pairs(masked, "(", ")")
    special_form_openings: set[int] = set()
    special_stack: list[bool] = []
    special_depth = 0
    for i, ch in enumerate(masked):
        if ch == "(":
            if special_depth:
                special_form_openings.add(i)
            special = i > 0 and masked[i - 1] in "$%@"
            special_stack.append(special)
            if special:
                special_depth += 1
        elif ch == ")" and special_stack:
            if special_stack.pop():
                special_depth -= 1
    brace_depth_at: dict[int, int] = {}
    depth = 0
    for i, ch in enumerate(masked):
        brace_depth_at[i] = depth
        if ch == "{": depth += 1
        elif ch == "}": depth = max(0, depth - 1)

    definitions: set[str] = set()
    prototypes: list[tuple[str, int]] = []
    for opening, closing in parens:
        if opening in special_form_openings:
            continue
        name = _call_name(masked, opening)
        if not name:
            continue
        open_line = _line_at(offsets, opening)
        close_line = _line_at(offsets, closing)
        line_start = offsets[open_line - 1]
        prefix = masked[line_start:opening]
        trailer = masked[closing + 1:masked.find("\n", closing + 1)
                         if "\n" in masked[closing + 1:] else len(masked)]

        if brace_depth_at.get(opening, 0) == 0 and _looks_like_declaration_prefix(prefix):
            if re.match(r"\s*;", trailer): prototypes.append((name, open_line))
            elif re.match(r"\s*(?:\{|=>)", trailer): definitions.add(name)

        if open_line == close_line:
            continue
        line_end = text.find("\n", opening)
        line_end = len(text) if line_end < 0 else line_end
        opening_has_content = bool(text[opening + 1:line_end].strip())
        if opening_has_content:
            add("violation", "wrapped_opening_line", open_line,
                "move all arguments or parameters to the continuation line")
        else:
            next_line = open_line
            while next_line < close_line and not lines[next_line].strip():
                next_line += 1
            if next_line < len(code_lines):
                indent = (len(code_lines[open_line - 1]) -
                          len(code_lines[open_line - 1].lstrip()))
                continuation = len(lines[next_line]) - len(lines[next_line].lstrip())
                if continuation != indent + 2:
                    add("violation", "continuation_indent", next_line + 1,
                        "arguments or parameters use a two-space continuation")
        close_column = closing - offsets[close_line - 1]
        if not lines[close_line - 1][:close_column].strip():
            if not _top_level_argument_is_multiline(
                    text, masked, opening, closing, offsets):
                add("violation", "standalone_closer", close_line,
                    "keep the close and trailer with the final argument or parameter")
        segment = text[opening:closing + 1]
        argument_multiline = _top_level_argument_is_multiline(
            text, masked, opening, closing, offsets)
        if (not argument_multiline and
                not any(_line_has_comment(x) for x in segment.splitlines())):
            collapsed = re.sub(r"\s+", " ", segment).strip()
            prefix_width = opening - line_start
            close_line_end = masked.find("\n", closing + 1)
            if close_line_end < 0:
                close_line_end = len(masked)
            suffix = masked[closing + 1:close_line_end].strip()
            suffix_width = len(suffix) + (1 if suffix else 0)
            if prefix_width + len(collapsed) + suffix_width <= 79:
                add("candidate", "horizontal_form", open_line,
                    "complete call or signature appears to fit horizontally")

    in_src = Path(path).parts and "src" in Path(path).parts
    in_lib = Path(path).parts and "lib" in Path(path).parts
    for name, line in prototypes:
        if in_src:
            add("violation", "forward_declaration", line,
                "user-space src code must rely on complete-unit collection")
        elif in_lib and name in definitions:
            add("candidate", "same_file_forward_declaration", line,
                "retain only for genuine co-recursion or literal shallow collection")
        else:
            add("candidate", "runtime_forward_declaration", line,
                "retain only for cross-unit co-recursion or literal shallow collection")

    # Braces around one executable statement obscure compact control flow.
    for opening, closing in _pairs(masked, "{", "}"):
        open_line = _line_at(offsets, opening)
        line_start = offsets[open_line - 1]
        prefix = masked[line_start:opening].strip()
        if not (re.search(r"\b(?:if|for|foreach|while)\s*\(.*\)\s*$", prefix) or
                re.search(r"\b(?:else|do)\s*$", prefix)):
            continue
        body = masked[opening + 1:closing]
        if "{" in body or "}" in body or "#" in body:
            continue
        if any(_line_has_comment(line) for line in text[opening + 1:closing].splitlines()):
            continue
        statement = body.strip()
        if statement.count(";") != 1 or not statement.endswith(";"):
            continue
        following = masked[closing + 1:].lstrip()
        if statement.startswith("if ") and following.startswith("else"):
            continue
        if re.fullmatch(r"(?:(?:const|unsigned|signed|long|short)\s+)*"
                        r"[A-Za-z_]\w*(?:\s*[*&]\s*|\s+)"
                        r"[A-Za-z_]\w*(?:\s*=.*)?;", statement, re.S):
            continue
        add("violation", "one_statement_braces", open_line,
            "omit braces around one executable statement")

    # Immediate declaration/assignment pairs are reliable initialization findings.
    declaration = re.compile(
        r"^(\s*)(?:(?:static|const|unsigned|signed|long|short)\s+)*"
        r"[A-Za-z_]\w*(?:\s*[*&]\s*|\s+)([A-Za-z_]\w*)\s*;\s*$")
    for i in range(len(code_lines) - 1):
        match = declaration.match(code_lines[i])
        if match and re.match(rf"^{re.escape(match.group(1))}{match.group(2)}\s*=", code_lines[i + 1]):
            add("violation", "deferred_initialization", i + 1,
                f"initialize {match.group(2)} where it becomes meaningful")

    # Repeated zero-argument accessors need a purity and receiver-stability review.
    accessor = re.compile(r"\b([A-Za-z_]\w*\.[A-Za-z_]\w*\(\))")
    occurrences: dict[tuple[int, str], list[int]] = {}
    for number, code in enumerate(code_lines, 1):
        pos = offsets[number - 1]
        block = brace_depth_at.get(pos, 0)
        for call in accessor.findall(code):
            occurrences.setdefault((block, call), []).append(number)
    for (_, call), numbers in occurrences.items():
        for start in range(len(numbers) - 2):
            if numbers[start + 2] - numbers[start] <= 12:
                add("candidate", "repeated_accessor", numbers[start],
                    f"{call} repeats three times; cache only if pure and stable")
                break

    # Adjacent constant stdout operations may be one byte-identical literal.
    output_call = re.compile(
        r'^\s*(?:puts\s*\(\s*"(?:\\.|[^"\\])*"\s*\)|'
        r'fputs\s*\(\s*"(?:\\.|[^"\\])*"\s*,\s*stdout\s*\))\s*;\s*$')
    run_start = run_length = 0
    for number, line in enumerate(lines + ["!"], 1):
        if output_call.match(line):
            if not run_length: run_start = number
            run_length += 1
        else:
            if run_length >= 2:
                add("candidate", "constant_output_run", run_start,
                    f"{run_length} adjacent static output calls; preserve emitted bytes")
            run_length = 0

    return sorted(findings, key=lambda f: (f.line, f.kind, f.category))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    text = args.path.read_text(encoding="utf-8")
    findings = analyze_text(str(args.path), text)
    violations = [f for f in findings if f.kind == "violation"]
    candidates = [f for f in findings if f.kind == "candidate"]
    print(f"style_violations: {len(violations)}")
    print(f"style_review_candidates: {len(candidates)}")
    for finding in findings:
        print(f"{finding.kind}:{finding.category}:{finding.line}:{finding.message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
