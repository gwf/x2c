"""Exercise edited files in one live REPL, including a real source module."""

import os
import pathlib
import queue
import subprocess
import sys
import threading


class Session:
    def __init__(self, directory):
        self.output = directory / "transcript"
        self.expected = []
        self.errors = queue.Queue()
        self.sequence = 0
        with self.output.open("w") as output:
            self.process = subprocess.Popen(
                ["builds/0/x2c", "repl"], text=True,
                stdin=subprocess.PIPE, stdout=output, stderr=subprocess.PIPE)
        self.reader = threading.Thread(target=self.read_errors, daemon=True)
        self.reader.start()

    def read_errors(self):
        for line in self.process.stderr:
            self.errors.put(line)
        self.errors.put(None)

    def run(self, source, error=None):
        # A unique inspection diagnostic marks completion while preserving
        # unfinished prompt input and adding no session definitions.
        self.sequence += 1
        marker = f"repl_reload_sync_{self.sequence}"
        self.process.stdin.write(f"{source}\n:info {marker}\n")
        self.process.stdin.flush()
        messages = []
        while True:
            line = self.errors.get(timeout=120)
            assert line is not None, (source, messages)
            if f"not a session function: {marker}" in line:
                break
            messages.append(line)
        diagnostic = "".join(messages)
        if error:
            assert error in diagnostic, (source, diagnostic)
        else:
            assert not diagnostic, (source, diagnostic)

    def value(self, expression, expected):
        self.run(expression + ";")
        self.expected.append("=> " + str(expected))

    def load(self, path, error=None):
        self.run(f':load "{path}"', error)

    def finish(self):
        self.process.stdin.close()
        # Synchronization diagnostics deliberately make the exit status one.
        assert self.process.wait(timeout=60) == 1
        self.reader.join(timeout=5)
        text = self.output.read_text()
        values = [line.rstrip() for line in text.splitlines()
                  if line.startswith("=> ")]
        assert values == self.expected, (values, self.expected, text)
        return text

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
            self.process.wait()


root = pathlib.Path(sys.argv[1]).resolve() / "reload"
root.mkdir()
dependency = root / "dependency.x"
native = root / "native.x"
second = root / "second.x"
alias = root / "alias.x"
alias.symlink_to(native)


def write_dependency(offset):
    dependency.write_text(
        "#pragma once\nmeta static int calls = 0;\n"
        f"meta int offset(int n) {{ calls++; return n + {offset}; }}\n"
        "meta int dependency_calls(void) { return calls; }\n")


def version(multiplier=3, parameter="renamed", result="Count", extra="",
            count="int", fields="int x; Part part;", answer=True, shape=True):
    text = ('#include "dependency.x"\n#include <stdlib.h>\n'
            f"typedef {count} Count;\n"
            "typedef struct Part { int value; } Part;\n"
            "enum LoadMode { LOAD_FIRST = 1, LOAD_SECOND };\n"
            "meta static int calls = 0;\n"
            "meta int loaded_calls(void) { return calls; }\n"
            "meta int loaded_dependency_calls(void) { return dependency_calls(); }\n"
            "meta void loaded_exit(void) { exit(8); }\n")
    if shape:
        text += f"typedef struct LoadShape {{ {fields} }} LoadShape;\n"
    if answer:
        text += (f"meta {result} loaded_answer(Count {parameter}) {{ calls++; "
                 f"return {multiplier} * offset({parameter}); }}\n")
    return text + extra


write_dependency(1)
native.write_text(version(2, "n"))
second.write_text(
    '#include "dependency.x"\n'
    "meta int second_answer(int n) { return offset(n); }\n"
    "meta int second_calls(void) { return dependency_calls(); }\n")
session = Session(root)
try:
    session.run("int before = 7;\nArray data = [4, 5];")
    session.load(native)
    session.run("int loaded_layout(void) { return sizeof(Count)==sizeof(int) "
                "&& offsetof(LoadShape,part)==sizeof(int); }")
    session.value("loaded_layout()", 1)
    session.run("Func saved = loaded_answer;\n"
                "Count through(Count n) { return loaded_answer(n) + before; }\n"
                "LoadShape shape={8,{9}};\n"
                "int change_shape(int n) { shape.part.value=n; return shape.x; }\n"
                "int load_mode(void) { enum LoadMode m=(enum LoadMode)2; return m; }")
    session.value("change_shape(10)", 8)
    session.value("shape.part.value", 10)
    session.value("load_mode()", 2)
    session.value("loaded_answer(20)", 42)
    session.value("saved(4)", 10)
    session.value("through(2)", 13)
    session.value("loaded_calls()", 3)
    session.load(second)
    session.value("second_answer(1)", 2)
    session.run(":info loaded_answer\n:info through\n:symbols loaded_a")
    session.value("loaded_calls()", 3)

    addition = "typedef int Added;\nmeta int added(void) { return 123; }\n"
    write_dependency(4)
    native.write_text(version(extra=addition))
    session.load(alias)
    session.value("loaded_calls()", 0)
    session.value("loaded_dependency_calls()", 0)
    session.value("second_calls()", 1)
    session.value("second_answer(1)", 2)
    session.value("loaded_answer(20)", 72)
    session.value("saved(4)", 24)
    session.value("through(2)", 25)
    session.value("before", 7)
    session.value("data.len()", "2ul")
    session.value("added()", 123)
    session.run("Added new_value = 11;")
    session.value("new_value", 11)

    # Even an unchanged successful load starts the file's variables afresh.
    session.load(pathlib.Path(os.path.relpath(native)))
    session.value("loaded_calls()", 0)
    session.value("second_calls()", 2)
    session.value("saved(2)", 18)

    rejected = [
        (version(extra=addition) + "meta int broken( {", "expected"),
        (version(result="long", extra=addition), "function type changed"),
        (version(answer=False, extra=addition), "function removed"),
        (version(count="long", extra=addition), "declaration changed or removed"),
        (version(fields="int x; int y;", extra=addition),
         "declaration changed or removed"),
        (version(shape=False, extra=addition), "declaration changed or removed"),
        (version(fields="int x; delegate Part part;", extra=addition),
         "conflicting declaration"),
        (version(extra=addition).replace(
            "typedef int Count;", "typedef int Count __attribute__((aligned(16)));"),
         "declaration changed or removed"),
        (version(extra=addition).replace("LOAD_FIRST = 1", "LOAD_FIRST = 100"),
         "declaration changed or removed"),
        (version(extra=addition).replace("LOAD_SECOND", "LOAD_RENAMED"),
         "declaration changed or removed"),
        (version(extra=addition + "meta int second_answer(int n) { return n; }\n"),
         "name already defined: second_answer"),
        (version(extra=addition + "meta int through(int n) { return n; }\n"),
         "name already defined: through"),
        (version(extra=addition + "struct through { int x; };\n"),
         "name already defined: through"),
        (version(extra=addition + "struct before { int x; };\n"),
         "name already defined: before"),
        (version(extra=addition + "struct added { int x; };\n"),
         "name already defined: added"),
        (version(extra=addition + "int absent(void);\n"
                 "meta int unlinked(void) { return absent(); }\n"), "absent"),
    ]
    calls = 1
    for text, error in rejected:
        native.write_text(text.replace("return 3 * offset", "return 19 * offset"))
        session.load(native, error)
        session.value("loaded_calls()", calls)
        session.value("second_calls()", 2)
        session.value("saved(2)", 18)
        calls += 1
        session.value("through(2)", 25)
        calls += 1
        session.value("loaded_calls()", calls)
    session.value("saved(2)", 18)
    session.value("loaded_calls()", calls + 1)

    native.write_text(version(4, extra=addition))
    session.load(native)
    session.value("loaded_calls()", 0)
    session.value("saved(2)", 24)
    native.write_text(version(9, result="long", extra=addition))
    session.load(native, "function type changed")
    session.run("loaded_exit();", "the body exited with status 8")
    session.value("loaded_calls()", 0)
    session.value("saved(2)", 24)
    session.run(":info missing", "not a session function")
    session.run(":info before", "not a session function")
    session.run(":symbols one two", "usage: :symbols")
    session.run("int unfinished =")
    session.run(":info loaded_answer\n:symbols loaded_a")
    session.run("9;")
    session.value("unfinished", 9)
    output = session.finish()
    assert output.count('reloaded (') == 3, output
    assert '%((native "loaded_answer"))' in output, output
    assert 'Count loaded_answer(Count);' in output, output
    assert 'Count through(Count);' in output and 'source: prompt' in output, output
    assert f'source: {native}' in output and f'source: {alias}' not in output, output
finally:
    session.close()

# Adding an earlier anonymous type must not change existing type identities.
types_root = root / "types"
types_root.mkdir()
types_file = types_root / "types.x"
point = "typedef struct { int x; int y; } Point;\ntypedef Point Same;\n"
extra = "typedef struct { int added; } Extra;\n"
ping = "meta int ping(void) { return 7; }\n"
types_file.write_text(point + ping)
session = Session(types_root)
try:
    session.load(types_file)
    session.run("Point p = {8, 9};\nSame s = {10, 11};")
    session.run("int point_sum(void) { return p.x+s.y; }")
    session.value("point_sum()", 19)
    types_file.write_text(extra + point + ping)
    session.load(types_file)
    session.value("point_sum()", 19)
    session.value("p.x", 8)
    session.value("p.y", 9)
    session.value("s.x", 10)
    session.run("Extra e = {12};\nPoint q = {13, 14};")
    session.value("e.added", 12)
    session.value("q.x", 13)
    shared = types_root / "shared.x"
    shared.write_text(point + "meta int shared_ping(void) { return 8; }\n")
    session.load(shared)
    session.run("int three_points(void) { return p.y+q.x+e.added; }")
    session.value("three_points()", 34)
    session.value("shared_ping()", 8)
    for changed in [
            "typedef struct { long x; int y; } Point;\ntypedef Point Same;\n",
            "typedef struct { const int x; int y; } Point;\ntypedef Point Same;\n",
            "typedef struct { int y; int x; } Point;\ntypedef Point Same;\n"]:
        types_file.write_text(extra + changed + ping)
        session.load(types_file, "declaration changed or removed")
        session.value("p.x", 8)
    split = ("typedef struct { int x; int y; } Point;\n"
             "typedef struct { int x; int y; } Same;\n")
    types_file.write_text(extra + split + ping)
    session.load(types_file, "declaration changed or removed")
    session.value("ping()", 7)
    session.finish()
finally:
    session.close()

# Loaded aliases can refer to an anonymous type first declared at the prompt.
owned_root = root / "prompt-types"
owned_root.mkdir()
owned_file = owned_root / "owned.x"
owned_file.write_text(point + "typedef Point Mirror;\n"
                      "typedef struct UsesPoint { Point point; } UsesPoint;\n" + ping)
session = Session(owned_root)
try:
    session.run(point)
    session.load(owned_file)
    session.run("int owned_types(void) { Mirror p={9,10}; "
                "UsesPoint v={{7,8}}; return p.x+v.point.x; }")
    session.value("owned_types()", 16)
    session.run("int point_size(void) { return sizeof(Point)==2*sizeof(int); }")
    session.value("point_size()", 1)
    session.finish()
finally:
    session.close()

# Exercise an existing package module without changing the checked-in source.
autodiff = root / "autodiff-macros.x"
original = pathlib.Path("packages/autodiff/src/autodiff-macros.x").read_text()
autodiff.write_text(original)
session = Session(root)
try:
    session.load(autodiff)
    session.run(':info ad_dot\n:symbols ad_do\nString label = "loss";\n'
                'String derive(void) { return ad_dot(label); }')
    session.value('ad_dot("loss")', '"loss_dot"')
    session.value("derive()", '"loss_dot"')
    session.value("ad_mutates(%(postfix ++ x))", 1)
    session.value('ad_unbind(%(at 17 (expr (int) (ident (binding 7 "x")))))',
                  '(expr (int) (ident ("x")))')
    before = 'meta String ad_dot(String name) => name + "_dot";'
    after = 'meta String ad_dot(String name) => name + "_derivative";'
    assert original.count(before) == 1
    autodiff.write_text(original.replace(before, after, 1))
    session.load(autodiff)
    session.value('ad_dot("loss")', '"loss_derivative"')
    session.value("derive()", '"loss_derivative"')
    session.value("label", '"loss"')
    output = session.finish()
    assert "String ad_dot(String);" in output, output
    assert '%((native "ad_dot"))' in output, output
finally:
    session.close()

print("REPL inspection and reload checks passed")
