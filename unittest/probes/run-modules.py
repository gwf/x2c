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
import shutil
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
    yield "declaration_scc_inline_providers", {
        "box.x": 'module {"box/left.x", "box/right.x"}\n',
        "box/left.x": (
            '#include "right.x"\n'
            'static typedef struct Left {int value;} Left;\n'
            'inline int left_value(void) {Left value = {17}; return value.value;}\n'
        ),
        "box/right.x": (
            '#include "left.x"\n'
            'static typedef struct Right {int value;} Right;\n'
            'inline int right_value(void) {Right value = {25}; return value.value;}\n'
        ),
        "main.x": consumer("box.x", "left_value() + right_value() == 42"),
    }, {"interface_inputs": ["box.x", "main.x"]}, None
    yield "nested_entry_member_equivalence", {
        "box.x": 'module {"box/state.x", "box/child.x"}\n',
        "box/state.x": 'module int offset = 40;\n',
        "box/child.x": 'module {"child/leaf.x"}\n',
        "box/child/leaf.x": 'module {"leaf/value.x"}\n',
        "box/child/leaf/value.x": (
            'static int increment(int value) => value + 2;\n'
            'int answer(void) => increment(offset);\n'
            'int main(void) => answer() == 42 ? 0 : 1;\n'
        ),
    }, {"inputs": ["box.x"], "member_equivalence": [
        "box.x", "box/child/leaf/value.x"]}, None
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
        "box/value.x": 'module typedef struct Opaque {int value;} *Opaque;\nmodule struct Opaque storage = {42};\nOpaque acquire(void) => &storage;\nint opaque_read(Opaque object) => object.value;\n',
        "main.x": consumer("box.x", "opaque_read(acquire()) == 42"),
    }, {}, None
    yield "native_consumer_inline_and_opaque", {
        "box.x": 'typedef struct Opaque *Opaque;\nmodule {"box/value.x"}\n',
        "box/value.x": (
            'module typedef struct Opaque {int value;} *Opaque;\n'
            'module struct Opaque storage = {41};\n'
            'module int increment(int value) => value + 1;\n'
            'Opaque acquire(void) => &storage;\n'
            'inline int opaque_answer(Opaque value) => increment(value.value);\n'
        ),
        "native.c": (
            '#include "box.h"\n'
            'int main(void) {Opaque value = acquire(); '
            'return opaque_answer(value) == 42 ? 0 : 1;}\n'
        ),
    }, {"inputs": ["box.x", "native.c"]}, None
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


def final_cases():
    hidden = {
        "box.x": 'module {"box/value.x"}\n',
        "box/value.x": 'module typedef struct Hidden {int value;} Hidden;\nint answer(void) => 42;\n',
    }
    yield "hidden_module_type_rejected", {
        **hidden,
        "main.x": '#include "box.x"\nint main(void) { Hidden value = {42}; return value.value == 42 ? 0 : 1; }\n',
    }, {}, r"Hidden"
    yield "public_signature_private_type_rejected", {
        **hidden,
        "box/value.x": 'module typedef struct Hidden {int value;} Hidden;\nHidden acquire(void) { Hidden value = {42}; return value; }\n',
        "main.x": '#include "box.x"\nint main(void) => 0;\n',
    }, {}, r"Hidden|private|public"
    yield "module_static_conflict", {
        "box.x": 'module {}\nmodule static int helper(void) => 42;\n',
        "main.x": '#include "box.x"\nint main(void) => 0;\n',
    }, {"rejection_phase": "parse"}, r"module.*static|static.*module"
    yield "prototype_visibility_conflict", {
        "box.x": 'module {}\nint helper(void);\nmodule int helper(void) => 42;\n',
        "main.x": '#include "box.x"\nint main(void) => 0;\n',
    }, {}, r"helper|visibility|private|public"
    yield "duplicate_membership_rejected", {
        "box.x": 'module {"box/value.x", "box/value.x"}\n',
        "box/value.x": 'int answer(void) => 42;\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"rejection_phase": "parse"}, r"duplicate|more than once"
    yield "missing_member_rejected", {
        "box.x": 'module {"box/missing.x"}\n',
        "main.x": '#include "box.x"\nint main(void) => 0;\n',
    }, {"rejection_phase": "parse"}, r"missing|readable|not found"
    yield "escaping_member_rejected", {
        "box.x": 'module {"outside.x"}\n',
        "outside.x": 'int answer(void) => 42;\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"rejection_phase": "parse"}, r"escape|companion"
    yield "ancestor_child_enrollment_rejected", {
        "box.x": 'module {"box/child.x", "box/child/value.x"}\n',
        "box/child.x": 'module {"child/value.x"}\n',
        "box/child/value.x": 'module int helper(void) => 42;\nint answer(void) => helper();\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"rejection_phase": "parse"}, r"both|ancestor|belongs|enroll"
    yield "unlisted_ordinary_file_rejected", {
        **FLAT,
        "box/unlisted.x": '#include "../box.x"\nint leak(void) => increment(41);\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {}, r"increment|private"
    yield "native_header_nearest_and_invalidation", {
        "box.x": 'module {"box/child.x"}\n',
        "box/child.x": 'module {"child/deep/value.x"}\n',
        "settings.h": '#define MODULE_HEADER_VALUE 7\n',
        "box/settings.h": '#define MODULE_HEADER_VALUE 42\n',
        "box/child/deep/value.x": '#include "settings.h"\nint answer(void) => MODULE_HEADER_VALUE;\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"inputs": ["box.x", "main.x"], "warm_builds": 1,
        "mutations": [{"box/settings.h": '#define MODULE_HEADER_VALUE 43\n',
                       "main.x": consumer("box.x", "answer() == 43")}]}, None
    yield "runtime_initialized_shared_map", {
        "box.x": 'module {"box/state.x", "box/work.x"}\n',
        "box/state.x": 'module Map shared = {answer: 41};\nmodule int read_state(void) => shared[<answer>];\n',
        "box/work.x": 'int answer(void) { shared[<answer>] = 42; return read_state(); }\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {}, None
    yield "nested_package_public_prefixes", {
        "packages/demo/src/demo.x": 'module {"demo/child.x"}\nint root_answer(void) => child_answer();\n',
        "packages/demo/src/demo/child.x": 'module {"child/value.x"}\n',
        "packages/demo/src/demo/child/value.x": 'module int helper(void) => 42;\nint child_answer(void) => helper();\n',
        "main.x": 'import "demo" as d with child_answer as local_child;\nint main(void) => d.root_answer() == 42 && local_child() == 42 ? 0 : 1;\n',
    }, {"package_dirs": ["packages"], "package_driver": True}, None
    yield "static_opaque_forward_regression", {
        "box.x": 'typedef struct Opaque *Opaque;\nmodule {"box/value.x"}\n',
        "box/value.x": 'static typedef struct Opaque {int value;} *Opaque;\nstatic struct Opaque storage = {42};\nOpaque acquire(void) => &storage;\nint opaque_read(Opaque object) => object.value;\n',
        "main.x": consumer("box.x", "opaque_read(acquire()) == 42"),
    }, {}, None


def generated_snapshot(output):
    return {path.relative_to(output).as_posix(): path.read_bytes()
            for path in output.rglob("*")
            if path.is_file() and path.suffix in {".c", ".h", ".xi", ".xnm"}}


def interface_replay(compiler, directory, inputs, fresh):
    output = directory / "interfaces"
    output.mkdir(exist_ok=True)
    command = [str(compiler), "translate", "-j", "1", "--out-dir", str(output)]
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
            generated = generated_snapshot(output)
            record["generated_files"] = sorted(generated)
            if mode == "warm":
                record["same_generated_code"] = generated == snapshots
            snapshots = generated
        records.append(record)
    return records


def member_equivalence(compiler, directory, entry, member):
    output = directory / "equivalence"
    records = []
    reference = None
    for invocation, source in (("entry", entry), ("member", member)):
        if output.exists():
            shutil.rmtree(output)
        output.mkdir()
        for mode in ("cold", "warm"):
            command = [str(compiler), "translate", "-j", "1", "--out-dir", str(output)]
            if mode == "cold":
                command.append("--no-interfaces")
            command.append(str(directory / source))
            translated = subprocess.run(command, cwd=directory, text=True,
                                        stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT)
            log = directory / f"equivalence-{invocation}-{mode}.log"
            log.write_text(translated.stdout)
            snapshot = generated_snapshot(output)
            if reference is None and translated.returncode == 0:
                reference = snapshot
            record = {"invocation": invocation, "mode": mode,
                      "command": command, "status": translated.returncode,
                      "generated_files": sorted(snapshot),
                      "same_generated_code": bool(snapshot) and snapshot == reference,
                      "different_files": sorted(
                          path for path in set(snapshot) | set(reference or {})
                          if snapshot.get(path) != (reference or {}).get(path)),
                      "log": str(log)}
            records.append(record)
        executable = directory / f"equivalence-{invocation}"
        command = [str(compiler), "build", "-j", "1", "--output", str(executable),
                   "--build-dir", str(directory / f"build-{invocation}"),
                   str(directory / source)]
        built = subprocess.run(command, cwd=directory, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = directory / f"equivalence-{invocation}-build.log"
        log.write_text(built.stdout)
        record = {"invocation": invocation, "mode": "executable",
                  "command": command, "status": built.returncode,
                  "log": str(log)}
        if not built.returncode:
            run = subprocess.run([str(executable)], cwd=directory, text=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            record["run_status"] = run.returncode
            (directory / f"equivalence-{invocation}-run.log").write_text(run.stdout)
        records.append(record)
    return records


def producer_execution(compiler, directory, inputs, counts):
    output = directory / "producer"
    output.mkdir()
    records = []
    for mode in ("cold", "warm"):
        command = [str(compiler), "translate", "-j", "1", "--out-dir", str(output)]
        if mode == "cold":
            command.append("--no-interfaces")
        command.extend(str(directory / source) for source in inputs)
        translated = subprocess.run(command, cwd=directory, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        log = directory / f"producer-{mode}.log"
        log.write_text(translated.stdout)
        actual = {text: translated.stdout.count(text) for text in counts}
        records.append({"mode": mode, "command": command,
                        "status": translated.returncode, "counts": actual,
                        "expected_counts": counts, "log": str(log)})
    return records


def run_case(compiler, base, name, files, options, rejection):
    directory = base / name
    directory.mkdir()
    for relative, text in files.items():
        path = directory / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="ascii")
    if options.get("capture_private_binding"):
        provider = directory / options["capture_private_binding"]
        captured = subprocess.run(
            [str(compiler), "translate", "-j", "1", "--dump-transforms", str(provider)],
            cwd=directory, text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT)
        (directory / "binding-capture.log").write_text(captured.stdout)
        binding = re.search(r'\(binding \d+ ("_x2c_mod_[A-Z0-9]+_helper")\)',
                            captured.stdout)
        if captured.returncode or not binding:
            return {"name": name, "passed": False,
                    "expected": "capture canonical private binding",
                    "log": str(directory / "binding-capture.log")}
        for relative in options["binding_targets"]:
            target = directory / relative
            target.write_text(target.read_text().replace(
                "CAPTURED_PRIVATE_BINDING", f"(binding-global {binding[1]})"))
    repository = Path(__file__).resolve().parents[2]
    for relative in options.get("package_dirs", []):
        for package in (directory / relative).iterdir():
            (package / "Makefile").write_text(
                f"PACKAGE := {package.name}\n"
                f"include {repository / 'packages/package.mk'}\n")
            if options.get("package_driver"):
                builds = package / "builds"
                builds.mkdir()
                preparation = [str(compiler), "build", "-j", "1", "--kind", "static-library",
                               "--package-dir", str(directory / relative),
                               "--output", str(builds / f"lib{package.name}.a"),
                               "--build-dir", str(builds / "cc"),
                               str(package / "src" / f"{package.name}.x")]
            else:
                preparation = ["make", "-C", str(package), "build",
                               f"X2C={compiler}", f"ROOT={compiler.parents[2]}",
                               "BUILD_JOBS=1"]
            prepared = subprocess.run(preparation, text=True,
                                      stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT)
            log = directory / "package-build.log"
            log.write_text(prepared.stdout)
            if not prepared.returncode and options.get("package_driver"):
                header = next((builds / "cc" / "gen").glob(
                    f"*/{package.name}.h"))
                shutil.copytree(header.parent, builds, dirs_exist_ok=True)
                for support in (builds / "cc" / "gen").rglob("*.h"):
                    shutil.copy2(support, builds / support.name)
                (builds / f"{package.name}.native.rsp").write_text("")
            if prepared.returncode:
                return {"name": name, "command": preparation,
                        "build_status": prepared.returncode, "passed": False,
                        "expected": "package build and executable exit 0",
                        "log": str(log)}
    executable = directory / "program"
    command = [str(compiler), "build", "-j", "1", "--output", str(executable),
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
    if options.get("run_log_counts"):
        counts = {text: program.stdout.count(text)
                  for text in options["run_log_counts"]}
        record["run_log_counts"] = counts
        record["passed"] &= counts == options["run_log_counts"]
    if options.get("build_log_counts"):
        counts = {text: result.stdout.count(text)
                  for text in options["build_log_counts"]}
        record["build_log_counts"] = counts
        record["passed"] &= counts == options["build_log_counts"]
    for relative, pattern in options.get("forbidden_transforms", {}).items():
        inspected = subprocess.run(
            [str(compiler), "translate", "-j", "1", "--dump-transforms",
             str(directory / relative)], cwd=directory, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (directory / "transforms.log").write_text(inspected.stdout)
        record["transform_status"] = inspected.returncode
        record["forbidden_transform"] = bool(re.search(pattern, inspected.stdout))
        record["passed"] &= inspected.returncode == 0 and not record["forbidden_transform"]
    if options.get("interface_inputs"):
        record["interface_replay"] = interface_replay(
            compiler, directory, options["interface_inputs"], True)
        record["passed"] &= all(
            item["status"] == 0 and item.get("same_generated_code", True)
            for item in record["interface_replay"])
    if options.get("member_equivalence"):
        record["member_equivalence"] = member_equivalence(
            compiler, directory, *options["member_equivalence"])
        record["passed"] &= all(
            item["status"] == 0 and item.get("same_generated_code", True)
            and item.get("run_status", 0) == 0
            for item in record["member_equivalence"])
    if options.get("producer_execution"):
        record["producer_execution"] = producer_execution(
            compiler, directory, options["producer_execution"],
            options["producer_counts"])
        record["passed"] &= all(
            item["status"] == 0 and item["counts"] == item["expected_counts"]
            for item in record["producer_execution"])
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
            if options.get("run_log_counts"):
                counts = {text: rerun.stdout.count(text)
                          for text in options["run_log_counts"]}
                status["run_log_counts"] = counts
                record["passed"] &= counts == options["run_log_counts"]
            (directory / f"rerun-{index}.log").write_text(rerun.stdout)
        record["repeat_statuses"].append(status)
        record["passed"] &= status.get("run") == 0
    return record



def protocol_cases():
    native = {
        "box.x": 'typedef int Amount;\nmodule {"box/protocol.x", "box/value.x"}\n',
        "box/protocol.x": 'module protocol int(T) {int T.absolute(T) = abs;}\nmodule protocol int(Amount);\n',
        "box/value.x": 'int answer(void) {Amount value = -42; return value.absolute();}\n',
    }
    yield "module_native_protocol_sibling", {
        **native, "main.x": consumer("box.x", "answer() == 42"),
    }, {"inputs": ["box.x", "main.x"], "warm_builds": 1}, None
    yield "module_protocol_meta_adoption", {
        "box.x": 'typedef int Amount;\nmodule {"box/protocol.x", "box/meta.x", "box/value.x"}\n',
        "box/protocol.x": 'module protocol int(T) {int T.absolute(T) = abs;}\nmeta module protocol int(Amount);\n',
        "box/meta.x": 'meta module int magnitude(int number) {Amount value = number; return value.absolute();}\n',
        "box/value.x": 'int answer(void) => $magnitude(-42);\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"inputs": ["box.x", "main.x"]}, None
    yield "module_protocol_external_rejected", {
        **native, "main.x": '#include "box.x"\nint main(void) {Amount value = -42; return value.absolute();}\n',
    }, {}, r"member|absolute|protocol"
    ordinary = {
        "box.x": 'typedef struct Base {int value;} Base;\ntypedef struct Amount {int value;} Amount;\nmodule {"box/protocol.x", "box/value.x"}\n',
        "box/protocol.x": 'module protocol Base(T) {int T.amount(T);}\nmodule int Base.amount(Base value) => value.value;\nmodule Base Amount.base(Amount value) => (Base) {value.value};\nmodule protocol Base(Amount);\n',
        "box/value.x": 'int answer(void) {Amount value = {42}; return value.amount();}\n',
    }
    yield "module_ordinary_protocol_default", {
        **ordinary, "main.x": consumer("box.x", "answer() == 42"),
    }, {"inputs": ["box.x", "main.x"]}, None
    yield "module_protocol_static_conflict", {
        "box.x": 'module {"box/protocol.x"}\n',
        "box/protocol.x": 'module static protocol int(T) {int T.absolute(T) = abs;}\n',
        "main.x": consumer("box.x", "1"),
    }, {"rejection_phase": "parse"}, r"module and static"
    yield "module_protocol_nested_ancestor", {
        "box.x": 'typedef int Amount;\nmodule {"box/protocol.x", "box/child.x"}\n',
        "box/protocol.x": native["box/protocol.x"],
        "box/child.x": 'module {"child/value.x"}\n',
        "box/child/value.x": native["box/value.x"],
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"inputs": ["box.x", "main.x"]}, None
    yield "module_protocol_repeated_public_base", {
        "common.x": 'typedef int Amount;\n',
        "left.x": '#include "common.x"\nmodule {"left/protocol.x", "left/value.x"}\n',
        "left/protocol.x": native["box/protocol.x"],
        "left/value.x": 'int first(void) {Amount value = -17; return value.absolute();}\n',
        "right.x": '#include "common.x"\nmodule {"right/protocol.x", "right/value.x"}\n',
        "right/protocol.x": native["box/protocol.x"],
        "right/value.x": 'int second(void) {Amount value = -25; return value.absolute();}\n',
        "main.x": '#include "left.x"\n#include "right.x"\nint main(void) => first() + second() == 42 ? 0 : 1;\n',
    }, {"inputs": ["common.x", "left.x", "right.x", "main.x"]}, None


"""Additional optional module scenarios; append ordering_cases() to selection."""


def ordering_cases():
    yield "keyword_alias_prefix_capture", {
        "box.x": (
            'macro Expression $offset() => 17;\n'
            'keyword captured $offset;\n'
            'module {"box/value.x"}\n'
            'macro Expression $offset() => 25;\n'
        ),
        "box/value.x": 'int answer(void) => captured();\n',
        "main.x": consumer(
            "box.x", "answer() == 17 && captured() == 17 && $offset() == 25"),
    }, {}, None
    yield "keyword_alias_suffix_rebinding", {
        "box.x": (
            'macro Expression $offset() => 17;\n'
            'keyword captured $offset;\n'
            'module {"box/value.x"}\n'
            'macro Expression $offset() => 25;\n'
            'keyword captured $offset;\n'
        ),
        "box/value.x": 'int answer(void) => captured();\n',
        "main.x": consumer("box.x", "answer() == 17 && captured() == 25"),
    }, {}, None
    prefix = 'macro Unit $produce(Name $name, Expr $value) { int $name(void) => $value; }\n'
    yield "declaration_producer_prefix", {
        "box.x": prefix + 'module {"box/value.x"}\n',
        "box/value.x": '$produce(answer, 42);\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {}, None
    yield "declaration_producer_executes_before_block_once", {
        "box.x": (
            'macro Unit $produce(Name $name) {\n'
            '  typedef $(let ((seen\n'
            '    (x2c.diagnostic.warn "MODULE_DECLARATION_ONCE" nil)))\n'
            "    '(int)) $name;\n"
            '}\n'
            '$produce(PrefixAmount);\n'
            'module {"box/value.x"}\n'
        ),
        "box/value.x": (
            'PrefixAmount answer(void) => 42;\n'
            'int main(void) => answer() == 42 ? 0 : 1;\n'
        ),
    }, {"inputs": ["box.x"], "producer_execution": ["box.x"],
        "producer_counts": {"macro: MODULE_DECLARATION_ONCE": 1}}, None
    yield "declaration_producer_suffix_not_inherited", {
        "box.x": 'module {"box/value.x"}\n' + prefix,
        "box/value.x": '$produce(answer, 42);\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"rejection_phase": "parse"}, r"unknown or forward-referenced macro.*produce"
    siblings = {
        "box.x": 'module {"box/producer.x", "box/value.x"}\n',
        "box/producer.x": prefix,
        "box/value.x": '$produce(answer, 42);\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }
    yield "sibling_declaration_producer_isolation", siblings, {
        "rejection_phase": "parse"}, r"unknown or forward-referenced macro.*produce"
    yield "sibling_declaration_producer_explicit_include", {
        **siblings,
        "box/value.x": '#include "producer.x"\n$produce(answer, 42);\n',
    }, {}, None
    yield "file_static_initializer_prerequisite_cycle", {
        "box.x": 'module {"box/state.x"}\n',
        "box/state.x": (
            'static String left = %"$right";\n'
            'static String right = %"$left";\n'
            'int answer(void) => 42;\n'
        ),
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"rejection_phase": "cache"}, r"file-static x2c initializer dependency cycle"
    yield "ordinary_include_cycle_is_not_initializer_cycle", {
        "box.x": 'module {"box/left.x", "box/right.x"}\n',
        "box/left.x": '#include "right.x"\nint first(void) => 20;\n',
        "box/right.x": '#include "left.x"\nint second(void) => 22;\n',
        "main.x": consumer("box.x", "first() + second() == 42"),
    }, {}, None


def privacy_cases():
    yield "nested_private_type_shadows_public_parent", {
        "box.x": 'typedef struct Choice {int parent;} Choice;\nint parent_answer(void) {Choice value = {2}; return value.parent;}\nmodule {"box/child.x"}\n',
        "box/child.x": 'module typedef struct Choice {int hidden;} Choice;\nmodule {"child/value.x"}\n',
        "box/child/value.x": 'int child_answer(void) {Choice value = {40}; return value.hidden;}\n',
        "main.x": consumer("box.x", "parent_answer() + child_answer() == 42"),
    }, {"inputs": ["box.x", "main.x"]}, None
    opaque = {
        "box.x": 'typedef struct Opaque *Opaque;\nmodule {"box/value.x"}\n',
        "box/value.x": 'module typedef struct Opaque {int value;} *Opaque;\nmodule struct Opaque storage = {42};\nOpaque acquire(void) => &storage;\n',
    }
    yield "opaque_public_forward_external_field_rejected", {
        **opaque, "main.x": '#include "box.x"\nint main(void) => acquire().value;\n',
    }, {}, r"field|member|aggregate|Opaque"
    captured = {
        "box.x": 'module int helper(void) => 42;\nmodule {"box/value.x"}\n',
        "box/value.x": 'int answer(void) => helper();\n',
    }
    constructed = 'macro Expression $captured() => $(quote (expr ((func ()) int) (ident CAPTURED_PRIVATE_BINDING)))();\n'
    yield "constructed_private_binding_inside_module", {
        **captured, "box/constructed.x": constructed + 'int copied_answer(void) => $captured();\n',
        "box.x": captured["box.x"].replace('"box/value.x"', '"box/value.x", "box/constructed.x"'),
        "main.x": consumer("box.x", "answer() == 42 && copied_answer() == 42"),
    }, {"inputs": ["box.x", "main.x"], "capture_private_binding": "box/value.x",
        "binding_targets": ["box/constructed.x"]}, None
    yield "constructed_private_binding_external_rejected", {
        **captured, "main.x": '#include "box.x"\n' + constructed + 'int main(void) => $captured();\n',
    }, {"capture_private_binding": "box/value.x", "binding_targets": ["main.x"]}, r"module-private declaration.*not accessible"


def initialization_cases():
    strings = {
        "box.x": 'module {"box/consumer.x", "box/provider.x"}\n',
        "box/consumer.x": 'module String copy = seed;\nint answer(void) => copy == "ready";\n',
        "box/provider.x": 'module String seed = "ready";\n',
        "main.x": consumer("box.x", "answer() == 1"),
    }
    yield "cross_file_initializer_reverse_order", strings, {
        "inputs": ["box/consumer.x", "box/provider.x", "box.x", "main.x"],
    }, None
    yield "cross_file_initializer_forward_order", strings, {
        "inputs": ["box/provider.x", "box/consumer.x", "box.x", "main.x"],
    }, None
    yield "cross_file_initializer_cycle_rejected", {
        "box.x": 'module {"box/left.x", "box/right.x"}\n',
        "box/left.x": 'module String left = %"L:$right";\nString first(void) => left;\n',
        "box/right.x": 'module String right = %"R:$left";\nString second(void) => right;\n',
        "main.x": consumer("box.x", "first() != NULL && second() != NULL"),
    }, {"inputs": ["box/left.x", "box/right.x", "box.x", "main.x"],
        "rejection_phase": "cache"}, r"initializer dependency cycle"
    yield "cross_file_map_identity_and_mutation", {
        "box.x": 'module {"box/consumer.x", "box/provider.x"}\n',
        "box/consumer.x": 'module Map alias = shared;\nint answer(void) { alias[<answer>] = 42; return alias == shared && shared[<answer>] == 42; }\n',
        "box/provider.x": 'module Map shared = {answer: 41};\n',
        "main.x": consumer("box.x", "answer() == 1 && answer() == 1"),
    }, {"inputs": ["box/consumer.x", "box/provider.x", "box.x", "main.x"]}, None


def staged_initialization_cases():
    files = {
        "box.x": 'module {"box/consumer.x", "box/provider.x"}\n',
        "box/consumer.x": 'module String copy = seed;\nint answer(void) => copy == "ready";\n',
        "box/provider.x": 'module String seed = "ready";\n',
        "main.x": consumer("box.x", "answer() == 1"),
    }
    yield "cross_file_initializer_provider_static_helper", {
        **files,
        "box/provider.x": 'static String make_seed(void) => "ready";\nmodule String seed = make_seed();\n',
    }, {"inputs": ["box.x", "main.x"]}, None
    yield "ordinary_consumer_public_module_initializer", {
        "box.x": 'module {"box/provider.x"}\n',
        "box/provider.x": 'String seed = "ready";\n',
        "main.x": '#include "box.x"\nString copy = seed;\nint main(void) => copy == "ready" ? 0 : 1;\n',
    }, {"inputs": ["main.x", "box.x"], "warm_builds": 1}, None
    yield "provider_local_initializer_macro", {
        **files,
        "box/provider.x": 'macro Expression $seed() => "ready";\nmodule String seed = $seed();\n',
    }, {"inputs": ["box.x", "main.x"]}, None
    yield "provider_initializer_owner_lisp_context", {
        **files,
        "box/provider.x": '$(defun initializer-owner-value () "ready")\nmacro Expression $seed() => $(x2c.literal.string (initializer-owner-value));\nmodule String seed = $seed();\n',
    }, {"inputs": ["box.x", "main.x"]}, None
    yield "initializer_macro_executes_once", {
        **files,
        "box.x": 'macro Expression $seed() => $(let ((seen (x2c.diagnostic.warn "MODULE_INITIALIZER_ONCE" nil))) (x2c.literal.string "ready"));\nmodule {"box/consumer.x", "box/provider.x"}\n',
        "box/provider.x": 'module String seed = $seed();\n',
    }, {"inputs": ["box.x", "main.x"],
        "build_log_counts": {"macro: MODULE_INITIALIZER_ONCE": 1}}, None
    yield "cross_file_initializer_retained_membership", files, {
        "inputs": ["box.x", "main.x"], "warm_builds": 1,
        "mutations": [{
            "box.x": 'module {"box/consumer.x", "box/provider.x", "box/new.x"}\n',
            "box/provider.x": 'module String seed = extra;\n',
            "box/new.x": 'module String extra = "ready";\n',
        }],
    }, None


def acceptance_cases():
    yield "exported_macro_private_capture_rejected", {
        "box.x": 'module int helper(void) => 42;\nmacro Expression $leak() using helper => helper();\nmodule {}\n',
        "main.x": '#include "box.x"\nint main(void) => $leak();\n',
    }, {}, r"module-private declaration.*not accessible"
    yield "parent_child_private_rejected", {
        "box.x": 'module {"box/child.x", "box/parent.x"}\n',
        "box/child.x": 'module {"child/value.x"}\n',
        "box/child/value.x": 'module int hidden(void) => 42;\n',
        "box/parent.x": 'int answer(void) => hidden();\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {}, r"hidden|private"
    yield "contextual_module_identifier", {
        "box.x": 'module {"box/value.x"}\n',
        "box/value.x": 'int module(int value) => value;\nint answer(void) { int module = 42; return module; }\n',
        "main.x": consumer("box.x", "answer() == 42 && module(42) == 42"),
    }, {}, None
    yield "unlisted_ordinary_file_positive", {
        **FLAT,
        "box/unlisted.x": '#include "../box.x"\nint ordinary(void) => answer();\n',
        "main.x": '#include "box/unlisted.x"\nint main(void) => ordinary() == 42 ? 0 : 1;\n',
    }, {}, None
    yield "external_private_variable_rejected", {
        "box.x": 'module {"box/value.x"}\n',
        "box/value.x": 'module int hidden = 42;\nint answer(void) => hidden;\n',
        "main.x": consumer("box.x", "hidden == 42"),
    }, {}, r"hidden|private"
    yield "retained_preamble_mutation", {
        "box.x": 'macro Expression $offset() => 17;\nmodule {"box/value.x"}\n',
        "box/value.x": 'int answer(void) => $offset();\n',
        "main.x": consumer("box.x", "answer() == $offset()"),
    }, {"inputs": ["box.x", "main.x"], "warm_builds": 1,
        "mutations": [{"box.x": 'macro Expression $offset() => 25;\nmodule {"box/value.x"}\n'}]}, None
    yield "retained_new_nearer_native_header", {
        "box.x": 'module {"box/child.x"}\n',
        "box/child.x": 'module {"child/deep/value.x"}\n',
        "settings.h": '#define MODULE_HEADER_VALUE 42\n',
        "box/child/deep/value.x": '#include "settings.h"\nint answer(void) => MODULE_HEADER_VALUE;\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"inputs": ["box.x", "main.x"], "warm_builds": 1,
        "mutations": [{"box/settings.h": '#define MODULE_HEADER_VALUE 43\n',
                       "main.x": consumer("box.x", "answer() == 43")}]}, None
    layout = {
        "box.x": 'module typedef struct Inner Inner;\nmodule typedef struct Outer Outer;\nmodule {"box/outer.x", "box/inner.x"}\n',
        "box/inner.x": 'module typedef struct Inner {int value;} Inner;\n',
        "box/outer.x": 'module typedef struct Outer {Inner inner;} Outer;\nint answer(void) { Outer value = {{42}}; return value.inner.value; }\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }
    yield "acyclic_by_value_layout", layout, {"inputs": ["box.x", "main.x"]}, None
    yield "cyclic_by_value_layout_rejected", {
        **layout, "box/inner.x": 'module typedef struct Inner {Outer outer;} Inner;\n',
        "box/outer.x": 'module typedef struct Outer {Inner inner;} Outer;\nint answer(void) => 42;\n',
    }, {"inputs": ["box.x", "main.x"], "rejection_phase": "any"}, r"incomplete|cycle|recursive"
    yield "module_global_class_shutdown_once", {
        "box.x": 'module {"box/state.x", "box/work.x"}\n',
        "box/state.x": 'module class Ticket struct {int value;} *;\nmodule void Ticket.init(Ticket ticket) { ticket.value = 42; puts("GLOBAL_INIT"); }\nmodule void Ticket.free(Ticket ticket) { puts("GLOBAL_FREE"); Scope.free(ticket); }\nmodule Ticket shared = Ticket.new();\nmodule void Ticket.shutdown(void) { shared.free(); puts("GLOBAL_SHUTDOWN"); }\n',
        "box/work.x": 'int answer(void) => shared.value;\n',
        "main.x": consumer("box.x", "answer() == 42 && answer() == 42"),
    }, {"inputs": ["box/work.x", "box/state.x", "box.x", "main.x"],
        "warm_builds": 1,
        "run_log_counts": {"GLOBAL_INIT": 1, "GLOBAL_FREE": 1, "GLOBAL_SHUTDOWN": 1}}, None


def forward_static_cases():
    files = {
        'box.x': 'module typedef struct Record { int value; } Record;\nmodule {"box/value.x"}\n',
        'box/value.x': 'int answer(void) { Record record = {42}; return record.head(); }\nstatic int Record.head(Record record) => record.value;\n',
        'main.x': '#include "box.x"\nint main(void) => answer() == 42 ? 0 : 1;\n',
    }
    yield 'forward_file_static_method_module_typedef', files, {'warm_builds':1, 'interface_inputs':list(files)}, None
    yield 'forward_file_static_method_external_rejected', {
        **files,
        'box.x':'typedef struct Record { int value; } Record;\nmodule {"box/value.x"}\n',
        'main.x':'#include "box.x"\nint main(void) { Record record = {42}; return record.head(); }\n',
    }, {}, r'head|member'
    yield 'forward_file_static_method_sibling_rejected', {
        **files,
        'box.x':'module typedef struct Record { int value; } Record;\nmodule {"box/value.x", "box/other.x"}\n',
        'box/other.x':'int sibling(void) { Record record = {42}; return record.head(); }\n',
    }, {}, r'head|member'


def multihop_initialization_cases():
    files = {
        "box.x": 'module {"box/state.x", "box/alias.x", "box/child.x"}\n',
        "box/state.x": (
            'module class Ticket struct {int value;} *;\n'
            'module void Ticket.init(Ticket ticket) {ticket.value = 42; puts("GLOBAL_INIT");}\n'
            'module void Ticket.free(Ticket ticket) {puts("GLOBAL_FREE"); Scope.free(ticket);}\n'
            'module Ticket shared = Ticket.new();\n'
            'module void Ticket.shutdown(void) {shared.free(); puts("GLOBAL_SHUTDOWN");}\n'
        ),
        "box/alias.x": 'module Ticket alias = shared;\n',
        "box/child.x": 'module {"child/state.x", "child/value.x"}\n',
        "box/child/state.x": 'module Ticket mirrored = alias;\n',
        "box/child/value.x": (
            'int answer(void) => mirrored == alias && alias == shared && mirrored.value == 42;\n'
        ),
        "main.x": consumer("box.x", "answer() && answer()"),
    }
    options = {"inputs": ["box/child/value.x", "box/alias.x", "box.x", "main.x"],
        "warm_builds": 1,
        "run_log_counts": {"GLOBAL_INIT": 1, "GLOBAL_FREE": 1, "GLOBAL_SHUTDOWN": 1}}
    yield "nested_multihop_member_type_initialization_once", files, options, None
    shared_type = 'module class Ticket struct {int value;} *;\n'
    yield "nested_multihop_entry_type_initialization_once", {
        **files,
        "box.x": shared_type + files["box.x"],
        "box/state.x": files["box/state.x"].replace(shared_type, ""),
    }, options, None


def local_shadow_cases():
    yield "local_shadow_of_initialized_module_object", {
        "box.x": 'module {"box/state.x"}\n',
        "box/state.x": 'static int create(void) => 42;\nint shared = create();\n',
        "main.x": '#include "box.x"\nint main(void) {int shared = 7; return shared == 7 ? 0 : 1;}\n',
    }, {"forbidden_transforms": {"main.x": r"_x2c_module_init_"}}, None



def compile_time_visibility_cases():
    # Each entry changes its binding after enrollment. Descendants receive
    # only the prefix, including each keyword alias's captured macro.
    prefixes = {
        "macro": (
            'module macro Expression $module_root_value() => 14;\n',
            'module macro Expression $module_child_value() => '
            '$module_root_value() + 14;\n',
            'module macro Expression $module_root_value() => 99;\n',
            'module macro Expression $module_child_value() => 99;\n',
            '$module_root_value() == 14 && $module_child_value() == 28'),
        "keyword": (
            'macro Expression $module_root_value() => 14;\n'
            'module keyword module_root_read $module_root_value;\n',
            'macro Expression $module_child_value() => 28;\n'
            'module keyword module_child_read $module_child_value;\n',
            'macro Expression $module_root_value() => 99;\n'
            'module keyword module_root_read $module_root_value;\n',
            'macro Expression $module_child_value() => 99;\n'
            'module keyword module_child_read $module_child_value;\n',
            'module_root_read() == 14 && module_child_read() == 28'),
        "lisp": (
            'module $(defun module-root-lisp () 14)\n',
            'module $(defun module-child-lisp () (+ (module-root-lisp) 14))\n',
            'module $(defun module-root-lisp () 99)\n',
            'module $(defun module-child-lisp () 99)\n',
            '$(module-root-lisp) == 14 && $(module-child-lisp) == 28'),
    }
    for family, (root, child, root_suffix, child_suffix, check) in prefixes.items():
        yield f"module_{family}_ancestor_child_prefix", {
            "box.x": root + 'module {"box/child.x"}\n' + root_suffix,
            "box/child.x": child + 'module {"child/value.x"}\n' + child_suffix,
            "box/child/value.x": f'int answer(void) => {check} ? 42 : 0;\n',
            "main.x": consumer("box.x", "answer() == 42"),
        }, {"interface_inputs": ["box.x", "box/child.x",
                                 "box/child/value.x", "main.x"]}, None

    # Explicit sibling includes prove the owner filter, rather than merely
    # the absence of implicit compile-time effects between member files.
    definitions = {
        "macro": (
            'module macro Expression $module_hidden_macro() => 42;\n',
            '$module_hidden_macro()', "parse", r"module_hidden_macro"),
        "keyword": (
            'macro Expression $module_alias_target() => 42;\n'
            'module keyword module_hidden_alias $module_alias_target;\n',
            'module_hidden_alias()', "any", r"undeclared function.*module_hidden_alias"),
        "lisp": (
            'module $(defun module-hidden-lisp () 42)\n',
            '$(module-hidden-lisp)', "macro", r"unbound.*module-hidden-lisp"),
    }
    for family, (definition, invocation, phase, diagnostic) in definitions.items():
        yield f"module_{family}_sibling_include_rejected", {
            "box.x": 'module {"box/left.x", "box/right.x"}\n',
            "box/left.x": definition + 'module {"left/value.x"}\n',
            "box/left/value.x": 'int left_answer(void) => 42;\n',
            "box/right.x": 'module {"right/value.x"}\n',
            "box/right/value.x": (
                '#include "../left.x"\n'
                f'int answer(void) => {invocation};\n'
            ),
            "main.x": consumer("box.x", "answer() == 42"),
        }, {"rejection_phase": phase}, diagnostic
        yield f"module_{family}_external_rejected", {
            "box.x": definition + 'module {"box/value.x"}\n',
            "box/value.x": 'int answer(void) => 42;\n',
            "main.x": consumer("box.x", f"{invocation} == 42"),
        }, {"rejection_phase": phase}, diagnostic
        yield f"module_{family}_entry_suffix_unavailable", {
            "box.x": 'module {"box/value.x"}\n' + definition,
            "box/value.x": f'int answer(void) => {invocation};\n',
            "main.x": consumer("box.x", "answer() == 42"),
        }, {"rejection_phase": phase}, diagnostic

def specification_gap_cases():
    yield "module_modifier_outside_membership_rejected", {
        "main.x": 'module int helper(void) => 42;\nint main(void) => helper() == 42 ? 0 : 1;\n',
    }, {"rejection_phase": "any"}, r"module|enrolled|member"
    yield "duplicate_immediate_owner_rejected", {
        "box.x": 'module {"box/value.x"}\n',
        "box.xp": 'module {"box/value.x"}\n',
        "box/value.x": 'int answer(void) => 42;\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"inputs": ["box/value.x", "main.x"], "rejection_phase": "any"}, r"owner|ambiguous|belongs|module"
    yield "nested_child_public_collision_rejected", {
        "box.x": 'module {"box/left.x", "box/right.x"}\n',
        "box/left.x": 'module {"left/value.x"}\n',
        "box/right.x": 'module {"right/value.x"}\n',
        "box/left/value.x": 'int answer(void) => 41;\n',
        "box/right/value.x": 'int answer(void) => 42;\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"inputs": ["box.x", "main.x"], "rejection_phase": "any"}, r"answer|duplicate|multiple|collision"
    yield "entry_static_macro_not_inherited", {
        "box.x": 'static macro Expression $entry_hidden() => 42;\nmodule {"box/value.x"}\n',
        "box/value.x": 'int answer(void) => $entry_hidden();\n',
        "main.x": consumer("box.x", "answer() == 42"),
    }, {"inputs": ["box.x", "main.x"], "rejection_phase": "any"}, r"entry_hidden|macro"
    yield "external_public_contributions_follow_member_order", {
        "box.x": 'module {"box/first.x", "box/second.x"}\n',
        "box/first.x": 'macro Expression $member_order() => 41;\n',
        "box/second.x": 'macro Expression $member_order() => 42;\n',
        "main.x": consumer("box.x", "$member_order() == 42"),
    }, {"inputs": ["box.x", "main.x"]}, None
    package = {
        "packages/demo/src/demo.x": 'module int hidden(void) => 42;\nmodule {"demo/child.x"}\n',
        "packages/demo/src/demo/child.x": 'module {"child/value.x"}\n',
        "packages/demo/src/demo/child/value.x": 'int answer(void) => hidden();\n',
        "main.x": 'import "demo" as d;\nint main(void) => d.answer() == 42 ? 0 : 1;\n',
    }
    package_options = {"package_dirs": ["packages"], "package_driver": True}
    yield "package_root_private_reaches_descendants", package, package_options, None
    yield "package_private_import_rejected", {
        **package,
        "main.x": 'import "demo" as d with hidden;\nint main(void) => hidden() == 42 ? 0 : 1;\n',
    }, {**package_options, "rejection_phase": "any"}, r"hidden|private|export"
    yield "legacy_package_without_module_block", {
        "packages/demo/src/demo.x": 'int answer(void) => 42;\n',
        "main.x": 'import "demo" as d with answer;\nint main(void) => d.answer() == 42 && answer() == 42 ? 0 : 1;\n',
    }, package_options, None
    yield "package_public_c_name_unchanged", {
        **package,
        "main.x": 'import "demo" as d;\nextern int check_public_c_name(void);\nint main(void) => d.answer() == 42 && check_public_c_name() ? 0 : 1;\n',
        "consumer.c": 'extern int demo__answer(void);\nint check_public_c_name(void) { return demo__answer() == 42; }\n',
    }, {**package_options, "inputs": ["main.x", "consumer.c"]}, None


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
    selected = list(cases()) + list(extended_cases()) + list(final_cases()) + list(protocol_cases()) + list(ordering_cases()) + list(privacy_cases()) + list(initialization_cases()) + list(staged_initialization_cases()) + list(acceptance_cases()) + list(forward_static_cases()) + list(local_shadow_cases()) + list(multihop_initialization_cases()) + list(compile_time_visibility_cases())
    selected += list(specification_gap_cases())
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
