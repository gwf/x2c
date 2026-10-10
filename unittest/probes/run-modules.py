#!/usr/bin/env python3
"""Run executable module scenarios with the compiler passed as argument.

This optional probe keeps its fixtures and logs in a fresh /tmp directory.
It exercises caller-visible behavior; it does not enroll a publication gate.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile


FLAT = {
    "box.x": 'module { "box/helpers.x", "box/value.x" }\n',
    "box/helpers.x": 'module int increment(int value) => value + 1;\n',
    "box/value.x": 'int answer(void) => increment(41);\n',
}

NESTED = {
    "box.x": 'module { "box/helpers.x", "box/child.x" }\n',
    "box/helpers.x": 'module int offset(void) => 40;\n',
    "box/child.x": 'module { "child/value.x" }\n',
    "box/child/value.x": 'int answer(void) => offset() + 2;\n',
}


def consumer(include, expression):
    return f'#include "{include}"\nint main(void) => ({expression}) ? 0 : 1;\n'


def cases():
    yield "flat_shared_helper", {
        **FLAT, "main.x": consumer("box.x", "answer() == 42")}, {}, None
    yield "external_private_rejected", {
        **FLAT, "main.x": consumer("box.x", "increment(41) == 42")}, {}, r"increment"
    yield "repeated_private_names", {
        "first.x": 'module { "first/value.x" }\n',
        "first/value.x": 'module int value(void) => 17;\nint first(void) => value();\n',
        "second.x": 'module { "second/value.x" }\n',
        "second/value.x": 'module int value(void) => 25;\nint second(void) => value();\n',
        "main.x": '#include "first.x"\n#include "second.x"\nint main(void) => first() + second() == 42 ? 0 : 1;\n',
    }, {}, None
    yield "nested_ancestor_helper", {
        **NESTED, "main.x": consumer("box.x", "answer() == 42")}, {}, None
    yield "nested_nearest_shadow", {
        **NESTED,
        "box/child/value.x": 'module int offset(void) => 6;\nint answer(void) => offset() * 7;\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {}, None
    yield "sibling_private_rejected", {
        "box.x": 'module { "box/left.x", "box/right.x" }\n',
        "box/left.x": 'module { "left/value.x" }\n',
        "box/left/value.x": 'module int hidden(void) => 42;\n',
        "box/right.x": 'module { "right/value.x" }\n',
        "box/right/value.x": 'int answer(void) => hidden();\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {}, r"hidden"
    yield "direct_member_include", {
        **FLAT, "main.x": consumer("box/value.x", "answer() == 42")}, {}, None
    yield "configured_include_root", {
        "library/box.x": 'module { "box/value.x" }\n',
        "library/box/value.x": 'module int helper(void) => 42;\nint answer(void) => helper();\n',
        "app/main.x": consumer("box.x", "answer() == 42"),
    }, {"include_dirs": ["library"]}, None
    yield "macro_preamble_order", {
        "box.x": 'macro Expression $module_probe_offset() => 3;\nmodule { "box/value.x" }\nmacro Expression $module_probe_offset() => 99;\n',
        "box/value.x": 'int answer(void) => $module_probe_offset();\n',
        "main.x": consumer("box.x", "answer() == 3 && $module_probe_offset() == 99"),
    }, {}, None
    yield "package_alias_and_with", {
        "packages/demo/src/demo.x": 'module { }\nmodule int helper(void) => 21;\nint answer(void) => helper() * 2;\n',
        "main.x": 'import "demo" as d with answer as local_answer;\nint main(void) => d.answer() == 42 && local_answer() == 42 ? 0 : 1;\n',
    }, {"package_dirs": ["packages"]}, None


def run_case(compiler, base, name, files, options, rejection):
    directory = base / name
    directory.mkdir()
    for relative, text in files.items():
        path = directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="ascii")
    repository = Path(__file__).resolve().parents[2]
    for relative in options.get("package_dirs", []):
        for package in (directory / relative).iterdir():
            (package / "Makefile").write_text(
                f"PACKAGE := {package.name}\n"
                f"include {repository / 'packages/package.mk'}\n")
            preparation = ["make", "-C", str(package), "build",
                           f"X2C={compiler}", f"ROOT={compiler.parents[2]}"]
            prepared = subprocess.run(preparation, text=True,
                                      stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT)
            log = directory / "package-build.log"
            log.write_text(prepared.stdout)
            if prepared.returncode:
                return {"name": name, "command": preparation,
                        "build_status": prepared.returncode, "passed": False,
                        "expected": "package build and executable exit 0",
                        "log": str(log)}
    executable = directory / "program"
    command = [str(compiler), "build", "--output", str(executable),
               "--build-dir", str(directory / "build")]
    for relative in options.get("include_dirs", []):
        command.extend(["-I", str(directory / relative)])
    for relative in options.get("package_dirs", []):
        command.extend(["--package-dir", str(directory / relative)])
    sources = [relative for relative in files
               if relative.endswith(".x") and not relative.startswith("packages/")]
    command.extend(str(directory / relative) for relative in sources)
    result = subprocess.run(command, cwd=directory, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (directory / "build.log").write_text(result.stdout)
    record = {"name": name, "command": command, "build_status": result.returncode,
              "log": str(directory / "build.log")}
    if rejection:
        record["expected"] = "translation rejection"
        record["passed"] = (result.returncode != 0 and
                            re.search(rejection, result.stdout, re.I) is not None and
                            ": type:" in result.stdout and
                            ": parse:" not in result.stdout and
                            "undefined symbol" not in result.stdout.lower())
        return record
    record["expected"] = "executable exit 0"
    if result.returncode:
        record["passed"] = False
        return record
    program = subprocess.run([str(executable)], cwd=directory, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (directory / "run.log").write_text(program.stdout)
    record["run_status"] = program.returncode
    record["passed"] = program.returncode == 0
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--case", action="append", default=[])
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    base = (args.output_dir.resolve() if args.output_dir else
            Path(tempfile.mkdtemp(prefix="x2c-module-probes-", dir="/tmp")))
    base.mkdir(parents=True, exist_ok=True)
    selected = list(cases())
    names = {case[0] for case in selected}
    unknown = set(args.case) - names
    if unknown:
        parser.error("unknown cases: " + ", ".join(sorted(unknown)))
    results = []
    for case in selected:
        if args.case and case[0] not in args.case:
            continue
        result = run_case(compiler, base, *case)
        results.append(result)
        print(("PASS " if result["passed"] else "FAIL ") + result["name"],
              flush=True)
    report = base / "results.json"
    report.write_text(json.dumps({"compiler": str(compiler), "cases": results},
                                indent=2) + "\n")
    print(f"{sum(result['passed'] for result in results)}/{len(results)} pass; {report}")
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
