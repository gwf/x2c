#!/usr/bin/env python3
"""Optional focused checks for the clone analysis experiment."""

import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def parse(text):
    tokens = iter(re.findall(r'"(?:\\.|[^"\\])*"|[()]|[^\s()]+', text))

    def value(token):
        if token == "(":
            result = []
            for child in tokens:
                if child == ")":
                    return result
                result.append(value(child))
            raise AssertionError("unterminated report list")
        if token.startswith('"'):
            return json.loads(token)
        number = re.fullmatch(r"(-?\d+)[ul]*", token)
        if number:
            return int(number[1])
        return token

    result = value(next(tokens))
    assert next(tokens, None) is None, "extra report output"
    return result


def run(tool, paths, *options):
    result = subprocess.run(
        [str(tool), "clones", *options, *map(str, paths)],
        check=True, capture_output=True, text=True,
    )
    return parse(result.stdout)


def fields(record):
    return {item[0]: item[1:] for item in record[1:]}


def stable(report):
    result = [report[0]]
    for section in report[1:]:
        if section[0] == "summary":
            section = [section[0]] + [
                item for item in section[1:]
                if not item[0].endswith("cpu-seconds")
            ]
        result.append(section)
    return result


def main():
    directory = Path(__file__).resolve().parent
    tool = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else (
        directory.parent / "builds" / "x2c-graph"
    )
    paths = [directory / "fixtures" / f"clones-{letter}.x"
             for letter in ("a", "b")]
    report = run(tool, paths)
    reverse = run(tool, paths[::-1])
    assert stable(report) == stable(reverse), "input order changed report"
    data = fields(report)
    summary = {item[0]: item[1] for item in data["summary"]}
    assert summary["units"] == 2
    assert summary["cons-visits"] > summary["unique-cells"] > 0
    assert summary["cell-bytes"] == summary["unique-cells"] * 24
    assert summary["suppressed-before-limit"] >= 1
    assert summary["minimum-size"] == 24
    assert summary["site-limit"] == 8
    buckets = [fields(bucket) for bucket in data["size-distribution"]]
    assert sum(bucket["unique-cells"][0] for bucket in buckets) == (
        summary["unique-cells"])
    assert sum(bucket["occurrences"][0] for bucket in buckets) == (
        summary["cons-visits"])
    for bucket in buckets:
        assert 0 <= bucket["repeated-cells"][0] <= bucket["unique-cells"][0]

    blocks = []
    groups = []
    for candidate in data["candidates"]:
        row = fields(candidate)
        sites = row["sites"]
        count = row["verified-occurrences"][0]
        assert len(sites) == min(count, summary["site-limit"])
        assert row["structural-occurrences"][0] >= count
        assert row["score"][0] == row["size"][0] * (count - 1)
        groups.append({site[1] for site in sites})
        if all(site[3] == ["kind", "block"] for site in sites):
            blocks.append({site[1] for site in sites})

    alpha = {"clone_alpha_a", "clone_alpha_b"}
    assert any(alpha <= group for group in blocks), "alpha match missing"
    for different in ("clone_repeated", "clone_literal", "clone_operator",
                      "clone_callee"):
        assert not any("clone_alpha_a" in group and different in group
                       for group in blocks), different
    assert not any({"clone_static_a", "clone_static_b"} <= group
                   for group in blocks), "static callee identities collapsed"
    for prefix in ("clone_local_prototype", "clone_local_extern"):
        assert not any({f"{prefix}_a", f"{prefix}_b"} <= group
                       for group in blocks), f"global identities lost: {prefix}"
    assert any({"clone_pointer_a", "clone_pointer_b"} <= group
               for group in blocks), "local function pointers did not match"
    assert any({"clone_nested_a", "clone_nested_b"} <= group
               for group in groups), "fragment-relative alpha match missing"

    larger = fields(run(tool, paths, "--min-size", "100"))
    larger_summary = {item[0]: item[1] for item in larger["summary"]}
    assert larger_summary["minimum-size"] == 100
    assert all(fields(candidate)["size"][0] >= 100
               for candidate in larger["candidates"])
    assert larger_summary["candidate-groups"] < summary["candidate-groups"]
    for invalid in ("0", "2147483648"):
        result = subprocess.run(
            [str(tool), "clones", "--min-size", invalid, *map(str, paths)],
            capture_output=True, text=True,
        )
        assert result.returncode == 2, f"accepted invalid minimum {invalid}"

    with tempfile.TemporaryDirectory(prefix="x2c-clones-") as temporary:
        many = Path(temporary) / "many.x"
        many.write_text("\n".join(
            f"int clone_many_{i}(int value) {{\n"
            "  int result = value + 17;\n"
            "  return result + 19;\n}"
            for i in range(10)
        ), encoding="ascii")
        repeated = fields(run(tool, [many]))["candidates"]
        assert any(fields(row)["verified-occurrences"] == [10]
                   and len(fields(row)["sites"]) == 8 for row in repeated), (
            "site truncation lost the full occurrence count")
    print("clone analysis checks passed")


if __name__ == "__main__":
    main()
