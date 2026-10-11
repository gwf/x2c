#!/usr/bin/env python3
"""Optional complete-layout controls; reuse the executable module harness."""

import argparse
import importlib.util
import json
from pathlib import Path
import tempfile
import subprocess
from types import SimpleNamespace


spec = importlib.util.spec_from_file_location(
    "module_probes", Path(__file__).with_name("run-modules.py"))
probes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probes)


def serial_run(command, **options):
    if len(command) > 1 and command[1] in ("build", "translate"):
        command[2:2] = ["-j", "1"]
    return subprocess.run(command, **options)


probes.subprocess = SimpleNamespace(
    run=serial_run, PIPE=subprocess.PIPE, STDOUT=subprocess.STDOUT)


def ordinary(files):
    result = {name: text.replace("module ", "")
              for name, text in files.items()}
    result["box.x"] = '#include "box/inner.x"\n#include "box/outer.x"\n'
    result["box/outer.x"] = '#include "inner.x"\n' + result["box/outer.x"]
    return result


def cases():
    original = next(case for case in probes.acceptance_cases()
                    if case[0] == "acyclic_by_value_layout")
    _, layout, options, rejection = original
    yield original
    yield "value_layout_reverse_order", {
        **layout, "box.x": layout["box.x"].replace(
            '"box/outer.x", "box/inner.x"',
            '"box/inner.x", "box/outer.x"')}, options, rejection
    yield "value_layout_direct_provider", layout, {
        "inputs": ["box/inner.x", "main.x"]}, None
    yield "value_layout_array_alias", {
        **layout,
        "box/outer.x": ('module typedef Inner Parts[2];\n'
                        'module typedef struct Outer {Parts inner;} Outer;\n'
                        'int answer(void) { Outer value = {{{17}, {25}}}; '
                        'return value.inner[0].value + value.inner[1].value; }\n'),
    }, options, None
    yield "value_layout_alias_provider_order", {
        **layout,
        "box/inner.x": ('module typedef struct Inner {int value;} Inner;\n'
                        'module typedef Inner Alias;\n'),
        "box/outer.x": ('module typedef Alias Parts[1];\n'
                        'module typedef struct Outer {Parts inner;} Outer;\n'
                        'int answer(void) { Outer value = {{{42}}}; '
                        'return value.inner[0].value; }\n'),
    }, options, None
    yield "value_layout_anonymous_field", {
        **layout,
        "box/outer.x": ('module typedef struct Outer {struct {Inner inner;};} Outer;\n'
                        'int answer(void) { Outer value = {{{42}}}; '
                        'return value.inner.value; }\n'),
    }, options, None
    yield "pointer_layout_cycle", {
        **layout,
        "box/inner.x": 'module typedef struct Inner {Outer *outer; int value;} Inner;\n',
        "box/outer.x": ('module typedef struct Outer {Inner *inner;} Outer;\n'
                        'int answer(void) { Inner inner = {NULL, 42}; '
                        'Outer outer = {&inner}; return outer.inner->value; }\n'),
    }, options, None
    yield next(case for case in probes.acceptance_cases()
               if case[0] == "cyclic_by_value_layout_rejected")
    packed = {
        **layout,
        "packed.h": ('typedef struct __attribute__((packed)) NativePacked '
                     '{char pad; int value;} NativePacked;\n'),
        "box/inner.x": ('#include "packed.h"\n'
                        'module typedef struct Inner {NativePacked packed;} Inner;\n'),
        "box/outer.x": ('module typedef struct Outer {Inner inner;} Outer;\n'
                        'int answer(void) { Outer value = {{{0, 42}}}; '
                        'return sizeof(NativePacked) == 5 '
                        '? value.inner.packed.value : 0; }\n'),
    }
    yield "unsupported_packed_provider", packed, options, None
    yield "ordinary_packed_provider", ordinary(packed), {
        "inputs": ["box.x", "box/inner.x", "box/outer.x", "main.x"]}, None
    yield "value_layout_native_prefix", {
        **layout, "settings.h": 'typedef int NativeWord;\n#define LAYOUT_OFFSET 42\n',
        "box/inner.x": '#include "settings.h"\nmodule typedef struct Inner {NativeWord value;} Inner;\n',
        "box/outer.x": ('module typedef struct Outer {Inner inner;} Outer;\n'
                        'int answer(void) { Outer value = {{42}}; '
                        'return value.inner.value; }\n'),
    }, options, None
    body_conditional = {
        **layout,
        "box/inner.x": ('#define SELECT_LAYOUT 1\n#if SELECT_LAYOUT\n'
                        'module typedef struct Inner {int value;} Inner;\n'
                        '#else\nmodule typedef struct Spare {long other;} Spare;\n'
                        '#endif\n'),
    }
    yield "value_layout_conditional_body", body_conditional, options, None
    yield "ordinary_conditional_body", ordinary(body_conditional), {
        "inputs": ["box.x", "box/inner.x", "box/outer.x", "main.x"]}, None
    alternate_body = {
        **layout,
        "box/inner.x": ('#define SELECT_LAYOUT 1\n#if SELECT_LAYOUT\n'
                        'module typedef struct Inner {int value;} Inner;\n'
                        '#else\nmodule typedef struct Inner {long value;} Inner;\n'
                        '#endif\n'),
    }
    yield "value_layout_conditional_alternatives", alternate_body, options, None
    yield "ordinary_conditional_alternatives", ordinary(alternate_body), {
        "inputs": ["box.x", "box/inner.x", "box/outer.x", "main.x"]}, None
    yield "value_layout_conditional_native_prefix", {
        **layout, "settings.h": 'typedef int NativeWord;\n',
        "box/inner.x": ('#define SELECT_LAYOUT 1\n#if SELECT_LAYOUT\n'
                        '#include "settings.h"\n#endif\n'
                        'module typedef struct Inner {NativeWord value;} Inner;\n'),
    }, options, None
    source_state = {
        **layout,
        "box/inner.x": ('inline int early(void) {\n#if defined(STATE_VALUE)\n'
                        'return 99;\n#else\nreturn 17;\n#endif\n}\n'
                        '#define STATE_VALUE 25\n'
                        'module typedef struct Inner {int value;} Inner;\n'),
        "box/outer.x": ('module typedef struct Outer {Inner inner;} Outer;\n'
                        'int answer(void) { Outer value = {{25}}; '
                        'return early() + value.inner.value; }\n'),
    }
    yield "value_layout_native_state_order", source_state, options, None
    yield "ordinary_native_state_order", ordinary(source_state), {
        "inputs": ["box.x", "box/inner.x", "box/outer.x", "main.x"]}, None
    header_state = {
        **layout,
        "settings.h": ('#ifndef LAYOUT_SETTINGS_H\n#define LAYOUT_SETTINGS_H\n'
                       '#define NATIVE_FEATURE 1\n'
                       'typedef struct NativeWord {int value;} NativeWord;\n'
                       '#endif\n'),
        "box/inner.x": ('inline int early(void) {\n#if defined(NATIVE_FEATURE)\n'
                        'return 99;\n#else\nreturn 17;\n#endif\n}\n'
                        '#include "settings.h"\n'
                        'module typedef struct Inner {NativeWord word;} Inner;\n'),
        "box/outer.x": ('module typedef struct Outer {Inner inner;} Outer;\n'
                        'int answer(void) { Outer value = {{{25}}}; '
                        'return early() + value.inner.word.value; }\n'),
    }
    yield "value_layout_native_header_state_order", header_state, options, None
    yield "ordinary_native_header_state_order", ordinary(header_state), {
        "include_dirs": ["."], "inputs": ["box.x", "box/inner.x", "box/outer.x", "main.x"]}, None
    yield next(case for case in probes.extended_cases()
               if case[0] == "opaque_public_forward")
    yield "value_layout_ancestor_alias_child_shadow", {
        "box.x": ('module typedef struct Inner Inner;\n'
                  'module typedef Inner RootAlias;\n'
                  'module {"box/inner.x", "box/child.x"}\n'),
        "box/inner.x": 'module typedef struct Inner {int value;} Inner;\n',
        "box/child.x": 'module {"child/outer.x"}\n',
        "box/child/outer.x": ('module typedef struct Inner {long wrong;} Inner;\n'
                              'module typedef struct Outer {RootAlias inner;} Outer;\n'
                              'int answer(void) { Outer outer = {{42}}; '
                              'return outer.inner.value; }\n'),
        "main.x": probes.consumer("box.x", "answer() == 42"),
    }, options, None
    yield "value_layout_file_static_prerequisite", {
        "box.x": ('module typedef struct Outer Outer;\n'
                  'module typedef struct Carrier Carrier;\n'
                  'module {"box/outer.x", "box/carrier.x", "box/other.x"}\n'),
        "box/outer.x": ('static typedef struct Hidden {int value;} Hidden;\n'
                        'module typedef struct Outer {Hidden hidden;} Outer;\n'),
        "box/carrier.x": ('module typedef struct Carrier {Outer outer;} Carrier;\n'
                          'int answer(void) { Carrier item = {{{42}}}; '
                          'return item.outer.hidden.value; }\n'),
        "box/other.x": ('static typedef struct Hidden {long other;} Hidden;\n'
                        'static int local(void) {Hidden item = {1}; '
                        'return item.other;}\n'),
        "main.x": probes.consumer("box.x", "answer() == 42"),
    }, options, None
    yield "value_layout_three_levels", {
        **layout,
        "box.x": ('module typedef struct Inner Inner;\n'
                  'module typedef struct Outer Outer;\n'
                  'module {"box/inner.x", "box/child.x"}\n'),
        "box/child.x": 'module {"child/deep.x"}\n',
        "box/child/deep.x": 'module {"deep/outer.x"}\n',
        "box/child/deep/outer.x": layout["box/outer.x"],
    }, options, None
    yield "value_layout_warm_replay", layout, {
        **options, "warm_builds": 1}, None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("compiler", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--case", action="append", default=[])
    args = parser.parse_args()
    base = args.output_dir or Path(tempfile.mkdtemp(prefix="x2c-layouts-", dir="/tmp"))
    base.mkdir(parents=True, exist_ok=True)
    results = []
    for case in cases():
        if args.case and case[0] not in args.case:
            continue
        result = probes.run_case(args.compiler.resolve(), base, *case)
        results.append(result)
        print(("PASS " if result["passed"] else "FAIL ") + case[0], flush=True)
    (base / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(f"{sum(row['passed'] for row in results)}/{len(results)} pass; {base}")
    return 0 if results and all(row["passed"] for row in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
