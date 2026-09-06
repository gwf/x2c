#!/usr/bin/env python3
"""Find source patterns that may perform unnecessary work.

The findings are a review queue, not proof that a source change is safe.
This scanner does not resolve x2c types or rewrite source.
"""

import argparse
import bisect
import json
import pathlib
import re
import sys

from x2c_source import function_spans, mask_non_code


RECEIVER = r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*"
APPEND_SELF = re.compile(
    rf"\b({RECEIVER})\s*=\s*\1\s*\.\s*append\s*\("
)
LOOP = re.compile(r"\b(?:for|foreach|while)\s*\(")
ITERATION_LIST = re.compile(rf"\b({RECEIVER})\s*\.\s*list\s*\(\s*\)")
TRAVERSAL = re.compile(
    rf"\b({RECEIVER})\s*(?:\.\s*(len|last)\s*\(\s*\)|(\[))"
)
CONTAINS_INSERT = re.compile(
    rf"(?:\belse\s+)?\bif\s*\(\s*!\s*({RECEIVER})"
    rf"\s*\.\s*contains\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"
    rf"\s*\)\s*(?:\{{\s*)?\1\s*\[\s*\2\s*\]\s*=",
    re.DOTALL,
)
CONCAT = re.compile(r"\.\s*concat\s*\(")


def matching(source, start, opening, closing):
    depth = 0
    for i in range(start, len(source)):
        if source[i] == opening:
            depth += 1
        elif source[i] == closing:
            depth -= 1
            if depth == 0:
                return i
    return None


def loop_ranges(masked):
    ranges = []
    for match in LOOP.finditer(masked):
        opening = masked.find("(", match.start(), match.end())
        closing = matching(masked, opening, "(", ")")
        if closing is None:
            continue
        body = closing + 1
        while body < len(masked) and masked[body].isspace():
            body += 1
        if body < len(masked) and masked[body] == "{":
            end = matching(masked, body, "{", "}")
        else:
            end = masked.find(";", body)
        if end is not None and end >= 0:
            ranges.append((match.start(), body, end + 1))
    return ranges


def function_ranges(masked):
    return [
        (span.declaration_start, span.end)
        for span in function_spans(masked, include_static=True)
    ]


def containing(ranges, position):
    candidates = [item for item in ranges
                  if item[0] <= position < item[-1]]
    return min(candidates, key=lambda item: item[-1] - item[0]) \
        if candidates else None


def line_number(starts, position):
    return bisect.bisect_right(starts, position)


def line_text(source, position):
    start = source.rfind("\n", 0, position) + 1
    end = source.find("\n", position)
    if end < 0:
        end = len(source)
    return source[start:end].strip()


def finding(path, source, starts, position, kind, pattern):
    return {
        "file": path.as_posix(),
        "line": line_number(starts, position),
        "kind": kind,
        "pattern": pattern,
        "text": line_text(source, position),
    }


def find_append(path, source, masked, starts, loops):
    results = []
    for match in APPEND_SELF.finditer(masked):
        loop = containing(loops, match.start())
        if loop and match.start() >= loop[1]:
            receiver = match.group(1)
            results.append(finding(
                path, source, starts, match.start(), "append-in-loop",
                f"{receiver} is appended back to itself inside a loop",
            ))
    return results


def find_iteration_lists(path, source, masked, starts, loops):
    results = []
    for match in ITERATION_LIST.finditer(masked):
        loop = containing(loops, match.start())
        if loop and match.start() < loop[1]:
            receiver = match.group(1)
            results.append(finding(
                path, source, starts, match.start(), "iteration-list",
                f"{receiver}.list() is used directly for iteration",
            ))
    return results


def find_repeated_traversals(path, source, masked, starts, functions):
    list_variables = {}
    for function in functions:
        body = masked[function[0]:function[1]]
        names = {
            match.group(1)
            for match in re.finditer(
                r"\bList\s+([A-Za-z_][A-Za-z0-9_]*)", body
            )
        }
        for match in re.finditer(r"\bList\s*\(([^)]*)\)", body):
            names.update(re.findall(
                r"\b[A-Za-z_][A-Za-z0-9_]*\b", match.group(1)
            ))
        list_variables[function] = names

    occurrences = {}
    for match in TRAVERSAL.finditer(masked):
        function = containing(functions, match.start())
        if not function:
            continue
        receiver = match.group(1)
        if receiver not in list_variables[function]:
            continue
        operation = match.group(2) or "index"
        key = (function, receiver, operation)
        occurrences.setdefault(key, []).append(match.start())

    results = []
    for (_, receiver, operation), positions in occurrences.items():
        cluster = [positions[0]]
        for position in positions[1:]:
            if (line_number(starts, position) -
                    line_number(starts, cluster[-1]) <= 8):
                cluster.append(position)
                continue
            if len(cluster) > 1:
                results.append((receiver, operation, cluster))
            cluster = [position]
        if len(cluster) > 1:
            results.append((receiver, operation, cluster))

    findings = []
    for receiver, operation, positions in results:
        count = len(positions)
        findings.append(finding(
            path, source, starts, positions[0], "repeated-traversal",
            f"{receiver}.{operation} is evaluated {count} times nearby",
        ))
    return findings


def find_contains_insert(path, source, masked, starts):
    results = []
    for match in CONTAINS_INSERT.finditer(masked):
        receiver, key = match.group(1), match.group(2)
        results.append(finding(
            path, source, starts, match.start(), "contains-then-insert",
            f"{receiver}.contains({key}) precedes {receiver}[{key}] insertion",
        ))
    return results


def find_concat_chains(path, source, masked, starts):
    results = []
    for match in CONCAT.finditer(masked):
        opening = masked.find("(", match.start(), match.end())
        closing = matching(masked, opening, "(", ")")
        if closing is None:
            continue
        following = closing + 1
        while following < len(masked) and masked[following].isspace():
            following += 1
        chained = CONCAT.match(masked, following)
        if chained:
            results.append(finding(
                path, source, starts, match.start(), "concat-chain",
                "concat() result is immediately concatenated again",
            ))
    return results


def scan(path, display):
    source = path.read_text(errors="strict")
    masked = mask_non_code(source)
    starts = [0] + [match.end() for match in re.finditer("\n", source)]
    loops = loop_ranges(masked)
    functions = function_ranges(masked)
    results = []
    results.extend(find_append(display, source, masked, starts, loops))
    results.extend(find_iteration_lists(
        display, source, masked, starts, loops
    ))
    results.extend(find_repeated_traversals(
        display, source, masked, starts, functions
    ))
    results.extend(find_contains_insert(display, source, masked, starts))
    results.extend(find_concat_chains(display, source, masked, starts))
    return results


def source_files(root, names):
    files = []
    for name in names:
        path = pathlib.Path(name)
        if not path.is_absolute():
            path = root / path
        if not path.exists():
            raise ValueError(f"path not found: {name}")
        if path.is_dir():
            files.extend(path.rglob("*.x"))
        elif path.is_file():
            files.append(path)
        else:
            raise ValueError(f"not a file or directory: {name}")
    return sorted(set(path.resolve() for path in files))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths", nargs="*", default=["src", "lib"],
        help="source files or directories to inspect (default: src lib)",
    )
    parser.add_argument(
        "--json", action="store_true", help="emit findings as JSON",
    )
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent

    try:
        files = source_files(root, args.paths)
        results = []
        for path in files:
            try:
                display = path.relative_to(root)
            except ValueError:
                display = path
            results.extend(scan(path, display))
    except (OSError, UnicodeError, ValueError) as error:
        print(f"find-unnecessary-operations: {error}", file=sys.stderr)
        return 1

    results.sort(key=lambda item: (
        item["file"], item["line"], item["kind"], item["pattern"]
    ))
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        for result in results:
            print(
                f'{result["file"]}:{result["line"]}\t'
                f'{result["pattern"]}\t{result["text"]}'
            )
    print(f"candidates={len(results)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
