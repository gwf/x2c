#!/usr/bin/env python3
"""Find public results discarded by production but consumed by tests.

The checked-in bootstrap is the production call surface because it contains
the generated C for src/ and lib/.  Calls in examples are production uses;
calls under unittest/ are test uses.  Report a non-void public function when
every production call discards its result and at least one test call uses it.
"""

import argparse
import json
import pathlib
import re
import sys


PROTOTYPE = re.compile(
    r"(?m)^([^#\n][^\n]*?)\s+([A-Za-z_][A-Za-z0-9_]*)"
    r"\s*\(([^;{}]*)\);\s*$"
)


def source_mask(source):
    masked = list(source)
    i = 0
    while i < len(source):
        if source.startswith("//", i):
            end = source.find("\n", i)
            end = len(source) if end < 0 else end
            masked[i:end] = " " * (end - i)
            i = end
        elif source.startswith("/*", i):
            end = source.find("*/", i + 2)
            end = len(source) - 2 if end < 0 else end
            for j in range(i, end + 2):
                if masked[j] != "\n":
                    masked[j] = " "
            i = end + 2
        elif source[i] in "\"'":
            quote = source[i]
            masked[i] = " "
            i += 1
            while i < len(source):
                if source[i] == "\\":
                    masked[i] = " "
                    i += 1
                    if i < len(source):
                        masked[i] = " "
                        i += 1
                elif source[i] == quote:
                    masked[i] = " "
                    i += 1
                    break
                else:
                    if masked[i] != "\n":
                        masked[i] = " "
                    i += 1
        else:
            i += 1
    return "".join(masked)


def public_results(root):
    results = {}
    for path in (root / "bootstrap").rglob("*.h"):
        source = path.read_text(errors="ignore")
        for match in PROTOTYPE.finditer(source):
            result = " ".join(match.group(1).split())
            if (result != "void" and
                    re.fullmatch(r"[A-Za-z_][A-Za-z0-9_ *]*", result)):
                results[match.group(2)] = result
    return results


def end_of_call(source, start):
    depth = 1
    i = start
    while i < len(source) and depth:
        if source[i] == "(":
            depth += 1
        elif source[i] == ")":
            depth -= 1
        i += 1
    return i if depth == 0 else None


def scan(paths, functions):
    names = re.compile(
        r"\b(" + "|".join(
            re.escape(name)
            for name in sorted(functions, key=len, reverse=True)
        ) + r")\s*\("
    )
    calls = {}
    for path in paths:
        source = path.read_text(errors="ignore")
        masked = source_mask(source)
        for match in names.finditer(masked):
            end = end_of_call(masked, match.end())
            if end is None:
                continue
            after = end
            while after < len(masked) and masked[after].isspace():
                after += 1
            if (after < len(masked) and masked[after] == "{") or \
                    re.match(r"=\s*>", masked[after:]):
                continue
            line_start = masked.rfind("\n", 0, match.start()) + 1
            prefix = masked[line_start:match.start()].strip()
            discarded = (
                after < len(masked) and masked[after] == ";" and
                prefix in ("", "(void)")
            )
            line = source.count("\n", 0, match.start()) + 1
            entry = calls.setdefault(
                match.group(1), {"discarded": [], "used": []}
            )
            entry["discarded" if discarded else "used"].append(
                f"{path}:{line}"
            )
    return calls


def call_paths(root, patterns):
    paths = []
    for pattern in patterns:
        paths.extend(root.glob(pattern))
    return sorted(set(path for path in paths if path.is_file()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", type=pathlib.Path,
        default=pathlib.Path(__file__).resolve().parent.parent,
        help="repository tree to inspect",
    )
    parser.add_argument("--json", type=pathlib.Path,
                        help="write the complete result as JSON")
    args = parser.parse_args()
    root = args.root.resolve()
    functions = public_results(root)
    if not functions:
        raise SystemExit(f"no bootstrap public functions found under {root}")

    production = scan(
        call_paths(root, ["bootstrap/**/*.c", "examples/**/*.x"]),
        functions,
    )
    tests = scan(call_paths(root, ["unittest/**/*.x"]), functions)
    results = []
    for name, calls in production.items():
        test_calls = tests.get(name, {"discarded": [], "used": []})
        if calls["discarded"] and not calls["used"] and test_calls["used"]:
            results.append({
                "function": name,
                "result": functions[name],
                "production_discarded": calls["discarded"],
                "test_used": test_calls["used"],
            })
    results.sort(key=lambda item: item["function"])
    if args.json:
        args.json.write_text(json.dumps(results, indent=2) + "\n")
    for result in results:
        print(
            f'{result["function"]}\t{result["result"]}\t'
            f'{len(result["production_discarded"])} discarded production\t'
            f'{len(result["test_used"])} used tests'
        )
        for site in result["production_discarded"][:3]:
            print(f"  production: {site}")
        for site in result["test_used"][:3]:
            print(f"  test: {site}")
    print(f"candidates={len(results)}", file=sys.stderr)


if __name__ == "__main__":
    main()
