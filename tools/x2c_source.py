#!/usr/bin/env python3
"""Mask comments and literals in x2c source for `tools/repo-metrics.py`.

`mask_non_code` is byte-length and newline preserving, so an offset into the
masked text indexes the raw text at the same position. Other tools read the
compiler's `--dump-definitions` projection or `x2c lint` instead.
"""

from __future__ import annotations

import re


CHAR_LITERAL = re.compile(r"'(?:\\.|[^\\'\n])+'")


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
