#!/usr/bin/env python3
"""Run executable module scenarios with the compiler passed as argument.

This optional probe keeps its fixtures and logs in a fresh /tmp directory.
It exercises caller-visible behavior; it does not enroll a publication gate.
"""

import argparse
import hashlib
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
    yield "direct_member_translation", {
        **FLAT,
        "box/value.x": "int main(void) => increment(41) == 42 ? 0 : 1;\n",
    }, {"inputs": ["box/value.x"]}, None
    yield "external_member_include_rejected", {
        **FLAT, "main.x": consumer("box/value.x", "answer() == 42"),
    }, {"rejection_phase": "parse"}, r"entry|owning|module"
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


def extended_cases():
    yield "three_levels_inherited_prefix", {
        "box.x": 'macro Expression $root_offset() => 1;\nmodule {"box/child.x"}\nmodule int base(void) => 36;\n',
        "box/child.x": 'macro Expression $middle_offset() => 2;\nmodule {"child/leaf.x"}\n',
        "box/child/leaf.x": 'macro Expression $leaf_offset() => 3;\nmodule {"leaf/value.x"}\n',
        "box/child/leaf/value.x": 'int answer(void) => base() + $root_offset() + $middle_offset() + $leaf_offset();\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {}, None
    yield "private_types_and_shared_object", {
        "box.x": 'module {"box/state.x", "box/write.x", "box/read.x"}\n',
        "box/state.x": 'module typedef struct State {int value;} State;\nmodule State shared = {41};\n',
        "box/write.x": 'void advance(void) { shared.value++; }\n',
        "box/read.x": 'int answer(void) => shared.value;\n',
        "main.x": '#include "box.x"\nint main(void) { advance(); return answer() == 42 ? 0 : 1; }\n',
    }, {}, None
    yield "public_collision_rejected", {
        "left.x": 'module {"left/value.x"}\n',
        "left/value.x": 'int answer(void) => 17;\n',
        "right.x": 'module {"right/value.x"}\n',
        "right/value.x": 'int answer(void) => 25;\n',
        "main.x": consumer("left.x", "answer() == 17"),
    }, {"rejection_phase": "any"}, r"duplicate|already.*defined|redefinition|conflict"
    yield "entry_suffix_declarations", {
        "box.x": 'module int early(void) => 20;\nmodule {"box/value.x"}\nmodule typedef struct Amount {int value;} Amount;\nmodule int late(Amount value) => value.value;\n',
        "box/value.x": 'int answer(void) { Amount value = {22}; return early() + late(value); }\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {}, None
    macros = {
        "box.x": 'module {"box/define.x", "box/value.x"}\n',
        "box/define.x": 'macro Expression $sibling_only() => 42;\n',
        "box/value.x": 'int answer(void) => $sibling_only();\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }
    yield "sibling_macro_isolation", macros, {"rejection_phase": "parse"}, r"sibling_only"
    yield "sibling_macro_explicit_include", {
        **macros, "box/value.x": '#include "define.x"\nint answer(void) => $sibling_only();\n',
    }, {}, None
    yield "initializer_shared_cleanup_cycle", {
        "box.x": 'module {"box/objects.x", "box/work.x"}\n',
        "box/objects.x": 'module class Ticket struct {int amount;} *;\nmodule Map shared = {answer: 41};\nmodule int drops = 0;\nmodule void Ticket.init(Ticket ticket) { ticket.amount = 21; }\nmodule void Ticket.free(Ticket ticket) { drops += ticket.amount; Scope.free(ticket); }\n#include "work.x"\nmodule int current_answer(void) => shared[<answer>];\n',
        "box/work.x": '#include "objects.x"\nint answer(void) { shared[<answer>] = 42; { Ticket ticket = $auto(Ticket.new()); } return current_answer() == 42 && drops == 21; }\n',
        "main.x": consumer("box.x", "answer() == 1"),
    }, {}, None
    yield "public_inline_private_helper", {
        "box.x": 'module {"box/value.x"}\n',
        "box/value.x": 'module int helper(int value) => value * 2;\ninline int answer(void) => helper(21);\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {}, None
    yield "opaque_public_forward", {
        "box.x": 'typedef struct Opaque *Opaque;\nmodule {"box/value.x"}\n',
        "box/value.x": 'static typedef struct Opaque {int value;} *Opaque;\nstatic struct Opaque storage = {42};\nOpaque acquire(void) => &storage;\nint opaque_read(Opaque object) => object.value;\n',
        "main.x": consumer("box.x", "opaque_read(acquire()) == 42"),
    }, {}, None
    yield "module_meta_function", {
        "box.x": 'module {"box/meta.x", "box/value.x"}\n',
        "box/meta.x": 'meta module int scale(int value) => value * 2;\n',
        "box/value.x": 'int answer(void) => $scale(21);\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {}, None
    yield "xp_owner", {
        "box.xp": 'module {"box/value.x"}\n',
        "box/value.x": 'module int helper(void) => 42;\nint answer(void) => helper();\n',
        "main.x": consumer("box.xp", "answer() == 42"),
    }, {}, None
    yield "repeated_member_basenames", {
        "left.x": 'module {"left/value.x"}\n',
        "left/value.x": 'module int helper(void) => 17;\nint first(void) => helper();\n',
        "right.x": 'module {"right/value.x"}\n',
        "right/value.x": 'module int helper(void) => 25;\nint second(void) => helper();\n',
        "main.x": '#include "left.x"\n#include "right.x"\nint main(void) => first() + second() == 42 ? 0 : 1;\n',
    }, {"warm_builds": 1}, None
    yield "cold_warm_membership_invalidation", {
        "box.x": 'module {"box/first.x"}\n',
        "box/first.x": 'module int helper(void) => 42;\nint answer(void) => helper();\n',
        "box/second.x": 'module int helper(void) => 43;\nint answer(void) => helper();\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"inputs": ["box.x", "main.x"], "warm_builds": 1,
        "interface_inputs": ["box.x", "box/first.x", "main.x"],
        "interface_inputs_after": ["box.x", "box/second.x", "main.x"],
        "mutations": [{"box.x": 'module {"box/second.x"}\n',
                       "main.x": consumer("box.x", "answer() == 43")}]}, None


def interface_replay(compiler, directory, inputs, fresh):
    output = directory / "interfaces"
    output.mkdir(exist_ok=True)
    command = [str(compiler), "translate", "--out-dir", str(output)]
    sources = [str(directory / path) for path in inputs]
    modes = ["cold", "warm"] if fresh else ["invalidated"]
    snapshots = None
    records = []
    for mode in modes:
        current = command + (["--no-interfaces"] if mode == "cold" else []) + sources
        translated = subprocess.run(current, cwd=directory, text=True,
                                    stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT)
        (directory / f"interface-{mode}.log").write_text(translated.stdout)
        record = {"mode": mode, "command": current,
                  "status": translated.returncode}
        if not translated.returncode:
            generated = {path.name: path.read_bytes()
                         for path in output.iterdir() if path.suffix in {".c", ".h"}}
            if mode == "warm":
                record["same_generated_code"] = generated == snapshots
            snapshots = generated
        records.append(record)
    return records


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
    sources = options.get("inputs", [relative for relative in files
               if relative.endswith((".x", ".xp")) and not relative.startswith("packages/")])
    command.extend(str(directory / relative) for relative in sources)
    result = subprocess.run(command, cwd=directory, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (directory / "build.log").write_text(result.stdout)
    record = {"name": name, "command": command, "build_status": result.returncode,
              "log": str(directory / "build.log")}
    if rejection:
        phase = options.get("rejection_phase", "type")
        record["expected"] = ("build rejection" if phase == "any" else
                              "translation rejection")
        record["passed"] = (result.returncode != 0 and
                            re.search(rejection, result.stdout, re.I) is not None and
                            (phase == "any" or f": {phase}:" in result.stdout) and
                            (phase != "type" or ": parse:" not in result.stdout) and
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
    if options.get("interface_inputs"):
        record["interface_replay"] = interface_replay(
            compiler, directory, options["interface_inputs"], True)
        record["passed"] &= all(
            item["status"] == 0 and item.get("same_generated_code", True)
            for item in record["interface_replay"])
    rounds = ([{}] * options.get("warm_builds", 0) +
              options.get("mutations", []))
    record["repeat_statuses"] = []
    for index, updates in enumerate(rounds):
        for relative, text in updates.items():
            (directory / relative).write_text(text, encoding="ascii")
        if updates and options.get("interface_inputs_after"):
            replay = interface_replay(
                compiler, directory, options["interface_inputs_after"], False)
            record["interface_replay"].extend(replay)
            record["passed"] &= all(item["status"] == 0 for item in replay)
        rebuilt = subprocess.run(command, cwd=directory, text=True,
                                 stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT)
        (directory / f"rebuild-{index}.log").write_text(rebuilt.stdout)
        status = {"build": rebuilt.returncode}
        if not rebuilt.returncode:
            rerun = subprocess.run([str(executable)], cwd=directory, text=True,
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT)
            status["run"] = rerun.returncode
            (directory / f"rerun-{index}.log").write_text(rerun.stdout)
        record["repeat_statuses"].append(status)
        record["passed"] &= status.get("run") == 0
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
    compiler_start = hashlib.sha256(compiler.read_bytes()).hexdigest()
    selected = list(cases()) + list(extended_cases())
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
    report.write_text(json.dumps({"compiler": str(compiler),
                                 "compiler_sha256_start": compiler_start,
                                 "compiler_sha256_end": hashlib.sha256(compiler.read_bytes()).hexdigest(),
                                 "cases": results},
                                indent=2) + "\n")
    print(f"{sum(result['passed'] for result in results)}/{len(results)} pass; {report}")
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
