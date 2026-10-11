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
    for visibility in ["static", "public"]:
        prefix = "static " if visibility == "static" else ""
        function_state = {
            **header_state,
            "box/inner.x": (prefix + 'int early_impl(void) {\n#if defined(NATIVE_FEATURE)\n'
                            'return 99;\n#else\nreturn 17;\n#endif\n}\n'
                            'int early(void) => early_impl();\n'
                            '#include "settings.h"\n'
                            'module typedef struct Inner {NativeWord word;} Inner;\n'),
        }
        yield "value_layout_native_header_" + visibility + "_body_order", function_state, options, None
        yield "ordinary_native_header_" + visibility + "_body_order", ordinary(function_state), {
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
    yield "value_layout_repeated_static_prerequisites", {
        "box.x": ('module typedef struct Outer Outer;\n'
                  'module typedef struct Other Other;\n'
                  'module {"box/outer.x", "box/other.x", "box/carrier.x"}\n'),
        "box/outer.x": ('static typedef struct Hidden {int value;} Hidden;\n'
                        'module typedef struct Outer {Hidden hidden;} Outer;\n'
                        'module Outer first(void) {Hidden item = {40}; '
                        'Outer outer = {item}; return outer;}\n'
                        'int shadow(void) {typedef struct Hidden {long wrong;} Hidden; '
                        'Hidden item = {42}; return item.wrong;}\n'),
        "box/other.x": ('static typedef struct Hidden {long other;} Hidden;\n'
                        'static typedef Hidden Parts[1];\n'
                        'module typedef struct Other {Parts hidden;} Other;\n'
                        'module Other second(void) {Parts item = {{2}}; '
                        'Other other = {{item[0]}}; return other;}\n'),
        "box/carrier.x": ('module typedef struct Carrier {Outer outer; Other other;} Carrier;\n'
                          'int answer(void) {Carrier value = {first(), second()}; '
                          'return value.outer.hidden.value + value.other.hidden[0].other;}\n'),
        "main.x": probes.consumer("box.x", "answer() == 42 && shadow() == 42"),
    }, options, None
    enum_layout = {
        **layout,
        "box/inner.x": ('static typedef enum Choice {MATCH = 17, COUNT = 1} Choice;\n'
                        'module typedef struct Inner {Choice choice; int items[COUNT];} Inner;\n'
                        'module Inner make(void) {Inner item = {MATCH, {25}}; return item;}\n'),
        "box/outer.x": ('module typedef struct Outer {Inner inner;} Outer;\n'
                        'int answer(void) {Outer item = {make()}; '
                        'return item.inner.choice + item.inner.items[0];}\n'),
    }
    yield "value_layout_static_enum", enum_layout, options, None
    yield "ordinary_static_enum", ordinary(enum_layout), {
        "inputs": ["box.x", "box/inner.x", "box/outer.x", "main.x"]}, None
    yield "value_layout_repeated_static_enumerators", {
        "box.x": 'module {"box/left.x", "box/right.x", "box/carrier.x"}\n',
        "box/left.x": ('static typedef enum Choice {MATCH = 17, COUNT = 1} Choice;\n'
                       'module typedef struct Left {Choice choice; int items[COUNT];} Left;\n'
                       'module Left first(void) {Left item = {MATCH, {1}}; return item;}\n'),
        "box/right.x": ('static typedef enum Choice {MATCH = 25, COUNT = 2} Choice;\n'
                        'module typedef struct Right {Choice choice; int items[COUNT];} Right;\n'
                        'module Right second(void) {Right item = {MATCH, {1, 2}}; return item;}\n'),
        "box/carrier.x": ('module typedef struct Carrier {Left left; Right right;} Carrier;\n'
                          'int answer(void) {Carrier value = {first(), second()}; '
                          'return sizeof(value.left.items) == sizeof(int) '
                          '&& sizeof(value.right.items) == 2 * sizeof(int) '
                          '? value.left.choice + value.right.choice : 0;}\n'),
        "main.x": probes.consumer("box.x", "answer() == 42"),
    }, options, None
    pointer_alias = {
        "box.x": 'module {"box/state.x", "box/mirror.x"}\n',
        "box/state.x": ('module typedef struct Ticket {int value;} *Ticket;\n'
                        'module Ticket ticket = NULL;\n'),
        "box/mirror.x": ('module typedef Ticket TicketAlias;\n'
                         'module TicketAlias mirror = NULL;\n'
                         'int answer(void) {return ticket == NULL && mirror == NULL ? 42 : 0;}\n'),
        "main.x": probes.consumer("box.x", "answer() == 42"),
    }
    yield "pointer_only_declared_alias", pointer_alias, options, None
    ordinary_pointer = {name: text.replace("module ", "")
                        for name, text in pointer_alias.items()}
    ordinary_pointer["box.x"] = '#include "box/state.x"\n#include "box/mirror.x"\n'
    ordinary_pointer["box/mirror.x"] = '#include "state.x"\n' + ordinary_pointer["box/mirror.x"]
    yield "ordinary_pointer_declared_alias", ordinary_pointer, {
        "inputs": ["box.x", "box/state.x", "box/mirror.x", "main.x"]}, None
    yield "pointer_only_opaque_alias", {
        **pointer_alias,
        "box/state.x": ('module struct Ticket;\n'
                        'module typedef struct Ticket *Ticket;\n'
                        'module Ticket ticket = NULL;\n'),
    }, options, None
    yield "pointer_array_alias_boundary", {
        **pointer_alias,
        "box/state.x": ('module typedef struct Ticket {int value;} *TicketSlots[2];\n'
                        'module TicketSlots ticket = {NULL, NULL};\n'),
        "box/mirror.x": ('module typedef TicketSlots SlotAlias;\n'
                         'module SlotAlias mirror = {NULL, NULL};\n'
                         'int answer(void) {return ticket[0] == NULL && mirror[1] == NULL ? 42 : 0;}\n'),
    }, options, None
    native_meta = {
        "box.x": ('module typedef struct Inner Inner;\n'
                  'module typedef struct Outer Outer;\n'
                  'meta module int probe(void);\n'
                  'module {"box/inner.x", "box/outer.x", "box/value.x"}\n'),
        "box/inner.x": 'module typedef struct Inner {int value;} Inner;\n',
        "box/outer.x": ('module typedef struct Outer {Inner inner;} Outer;\n'
                        'meta module int probe(void) {Outer value = {{42}}; '
                        'return value.inner.value;}\n'),
        "box/value.x": 'int answer(void) => $probe();\n',
        "main.x": probes.consumer("box.x", "answer() == 42"),
    }
    yield "native_meta_complete_layout", native_meta, options, None
    ordinary_meta = {name: text.replace("module ", "")
                     for name, text in native_meta.items()}
    ordinary_meta["box.x"] = ('#include "box/inner.x"\n#include "box/outer.x"\n'
                              '#include "box/value.x"\n')
    ordinary_meta["box/outer.x"] = '#include "inner.x"\n' + ordinary_meta["box/outer.x"]
    ordinary_meta["box/value.x"] = '#include "outer.x"\n' + ordinary_meta["box/value.x"]
    yield "ordinary_native_meta_complete_layout", ordinary_meta, {
        "inputs": ["box.x", "box/inner.x", "box/outer.x", "box/value.x", "main.x"]}, None
    conditional_pointer = {
        **pointer_alias,
        "box/state.x": ('#define USE_FIRST 1\n#if USE_FIRST\n'
                        'module typedef struct First {int value;} *Ticket;\n'
                        '#else\nmodule typedef struct Second {long other;} *Ticket;\n'
                        '#endif\nmodule Ticket ticket = NULL;\n'),
    }
    yield "pointer_alias_conditional_variants", conditional_pointer, options, None
    ordinary_conditional_pointer = {
        name: text.replace("module ", "")
        for name, text in conditional_pointer.items()}
    ordinary_conditional_pointer["box.x"] = '#include "box/state.x"\n#include "box/mirror.x"\n'
    ordinary_conditional_pointer["box/mirror.x"] = (
        '#include "state.x"\n' + ordinary_conditional_pointer["box/mirror.x"])
    yield "ordinary_pointer_alias_conditional_variants", ordinary_conditional_pointer, {
        "inputs": ["box.x", "box/state.x", "box/mirror.x", "main.x"]}, None
    native_alias = {
        "box.x": 'module {"box/state.x", "box/mirror.x"}\n',
        "settings.h": 'typedef int NativeWord;\n#define WORD_PAD 1\n',
        "box/state.x": ('#include "settings.h"\n'
                        'module typedef NativeWord Word;\n'
                        'module typedef struct Ticket {Word value;} *Ticket;\n'
                        'module Word number = 17;\nmodule Ticket ticket = NULL;\n'),
        "box/mirror.x": ('module typedef Word MirrorWord;\n'
                         'module MirrorWord mirror = 25;\n'
                         'int answer(void) {return number + mirror;}\n'),
        "main.x": probes.consumer("box.x", "answer() == 42"),
    }
    yield "native_dependent_alias_forward", native_alias, {
        **options, "include_dirs": ["."]}, None
    ordinary_native_alias = {name: text.replace("module ", "")
                             for name, text in native_alias.items()}
    ordinary_native_alias["box.x"] = '#include "box/state.x"\n#include "box/mirror.x"\n'
    ordinary_native_alias["box/mirror.x"] = '#include "state.x"\n' + ordinary_native_alias["box/mirror.x"]
    yield "ordinary_native_dependent_alias_forward", ordinary_native_alias, {
        "include_dirs": ["."],
        "inputs": ["box.x", "box/state.x", "box/mirror.x", "main.x"]}, None
    for flag in (0, 1):
        exclusive_layout = {
            "box.x": 'module {"box/inner.x", "box/outer.x"}\n',
            "box/inner.x": (f'#define SELECT_LAYOUT {flag}\n#if SELECT_LAYOUT\n'
                            'module typedef struct A {int value;} A;\n'
                            'module typedef struct B {A nested;} B;\n'
                            '#else\nmodule typedef struct B {int value;} B;\n'
                            'module typedef struct A {B nested;} A;\n#endif\n'),
            "box/outer.x": ('module typedef struct Outer {A first; B second;} Outer;\n'
                            'int answer(void) {return sizeof(Outer) == 2 * sizeof(int) ? 42 : 0;}\n'),
            "main.x": probes.consumer("box.x", "answer() == 42"),
        }
        yield f"exclusive_layout_edges_flag_{flag}", exclusive_layout, options, None
        yield f"ordinary_exclusive_layout_edges_flag_{flag}", ordinary(exclusive_layout), {
            "inputs": ["box.x", "box/inner.x", "box/outer.x", "main.x"]}, None
    for storage in ("", "static "):
        label = "static" if storage else "public"
        macro_effects = {
            **layout,
            "settings.h": ('#ifndef LAYOUT_SETTINGS_H\n#define LAYOUT_SETTINGS_H\n'
                           '#undef NATIVE_FEATURE\n#define NATIVE_FEATURE 1\n'
                           'typedef int NativeWord;\n#endif\n'),
            "box/inner.x": ('#define NATIVE_FEATURE 0\n' + storage +
                            'int early(void) {\n#if NATIVE_FEATURE == 1\n'
                            'return 1;\n#else\nreturn 0;\n#endif\n}\n'
                            '#include "settings.h"\n'
                            'module typedef struct Inner {NativeWord value;} Inner;\n'
                            'int readstate(void) {return early();}\n'),
            "box/outer.x": ('module typedef struct Outer {Inner inner;} Outer;\n'
                            'int answer(void) {Outer item = {{41}}; '
                            'return readstate() + item.inner.value;}\n'),
        }
        yield f"guarded_header_macro_effects_{label}", macro_effects, {
            **options, "include_dirs": ["."]}, None
        yield f"ordinary_guarded_header_macro_effects_{label}", ordinary(macro_effects), {
            "include_dirs": ["."],
            "inputs": ["box.x", "box/inner.x", "box/outer.x", "main.x"]}, None
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
