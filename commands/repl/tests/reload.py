"""Exercise edited files in one live REPL, including a real source module."""

import json
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
            prefix, found, _ = line.partition(
                f"not a session function: {marker}")
            if found:
                messages.append(prefix)
                break
            messages.append(line)
        diagnostic = "".join(messages)
        if error is True:
            assert diagnostic, source
        elif error:
            assert error in diagnostic, (source, diagnostic)
        else:
            assert not diagnostic, (source, diagnostic)

    def value(self, expression, expected):
        self.run(expression + ";")
        self.expected.append("=> " + str(expected))

    def snapshot(self, expression, expected):
        start = len(self.output.read_text())
        self.run(expression + ';')
        shown = self.output.read_text()[start:].strip()
        assert shown.startswith('=> '), shown
        assert json.loads(shown[3:]) == expected, shown
        self.expected.append(shown.splitlines()[0])

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
        "#pragma once\nstatic int calls = 0;\n"
        f"int offset(int n) {{ calls++; return n + {offset}; }}\n"
        "int dependency_calls(void) { return calls; }\n")


def version(multiplier=3, parameter="renamed", result="Count", extra="",
            count="int", fields="int x; Part part;", answer=True, shape=True):
    text = ('#include "dependency.x"\n#include <stdlib.h>\n'
            f"typedef {count} Count;\n"
            "typedef struct Part { int value; } Part;\n"
            "enum LoadMode { LOAD_FIRST = 1, LOAD_SECOND };\n"
            "static int calls = 0;\n"
            "int loaded_calls(void) { return calls; }\n"
            "int loaded_dependency_calls(void) { return dependency_calls(); }\n"
            "void loaded_exit(void) { exit(8); }\n")
    if shape:
        text += f"typedef struct LoadShape {{ {fields} }} LoadShape;\n"
    if answer:
        text += (f"{result} loaded_answer(Count {parameter}) {{ calls++; "
                 f"return {multiplier} * offset({parameter}); }}\n")
    return text + extra


write_dependency(1)
native.write_text(version(2, "n"))
second.write_text(
    '#include "dependency.x"\n'
    "int second_answer(int n) { return offset(n); }\n"
    "int second_calls(void) { return dependency_calls(); }\n")
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
    session.value("loaded_calls()", 0)

    addition = "typedef int Added;\nint added(void) { return 123; }\n"
    write_dependency(4)
    native.write_text(version(extra=addition))
    session.load(alias)
    session.value("loaded_calls()", 0)
    session.value("loaded_dependency_calls()", 0)
    session.value("second_calls()", 0)
    session.value("second_answer(1)", 5)
    session.value("loaded_answer(20)", 72)
    session.value("saved(4)", 24)
    session.value("through(2)", 25)
    session.value("before", 7)
    session.value("data.len()", "2ul")
    session.value("added()", 123)
    session.run("Added new_value = 11;")
    session.value("new_value", 11)

    # Even an unchanged load resets every provider's native state.
    session.load(pathlib.Path(os.path.relpath(native)))
    session.value("loaded_calls()", 0)
    session.value("second_calls()", 0)
    session.value("saved(2)", 18)

    rejected = [
        (version(extra=addition) + "int broken( {", "expected"),
        (version(result="long", extra=addition), "function type changed"),
        (version(answer=False, extra=addition), "loaded_answer is "),
        (version(extra=addition).replace(
            "Count loaded_answer", "static Count loaded_answer"),
         "loaded_answer is "),
        (version(count="long", extra=addition), "declaration changed"),
        (version(fields="int x; int y;", extra=addition),
         "declaration changed"),
        (version(shape=False, extra=addition), "LoadShape is used by prompt "),
        (version(fields="int x; delegate Part part;", extra=addition),
         "conflicting declaration"),
        (version(extra=addition).replace(
            "typedef int Count;", "typedef int Count __attribute__((aligned(16)));"),
         "declaration changed"),
        (version(extra=addition).replace("LOAD_FIRST = 1", "LOAD_FIRST = 100"),
         "declaration changed"),
        (version(extra=addition).replace("LOAD_SECOND", "LOAD_RENAMED"),
         "declaration changed"),
        (version(extra=addition + "int second_answer(int n) { return n; }\n"),
         True),
        (version(extra=addition + "int through(int n) { return n; }\n"),
         "name already defined: through"),
        (version(extra=addition + "struct through { int x; };\n"),
         "name already defined: through"),
        (version(extra=addition + "struct before { int x; };\n"),
         "name already defined: before"),
        (version(extra=addition + "struct added { int x; };\n"),
         "name already defined: added"),
        (version(extra=addition + "int absent(void);\n"
                 "int unlinked(void) { return absent(); }\n"), "absent"),
    ]
    calls = 1
    for text, error in rejected:
        native.write_text(text.replace("return 3 * offset", "return 19 * offset"))
        session.load(native, error)
        session.value("loaded_calls()", calls)
        session.value("second_calls()", calls)
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
    session.value("second_calls()", 0)
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

# Ordinary public entries do not expose statics, prototypes, or included
# definitions. C sources use the same visibility boundary as x2c sources.
for extension in ("x", "c"):
    public_root = root / ("public-" + extension)
    public_root.mkdir()
    public_file = public_root / ("public." + extension)
    other_file = public_root / ("other." + extension)
    dependency_file = public_root / "dependency.x"
    dependency_file.write_text(
        "int public_dependency(int n) { return n + 1; }\n")
    contents = ('#include "dependency.x"\n'
                'static int private_twice(int n) { return 2*n; }\n'
                'static int private_later(int n);\n'
                'int private_later(int n) { return n+1; }\n'
                'meta static int private_meta(int n) { return n+1; }\n'
                'int public_prototype(int n);\n'
                'int public_answer(int n) { return private_twice('
                'private_later(private_meta(public_dependency(n)))); }\n'
                'meta int public_meta(int n) { return public_answer(n); }\n')
    public_file.write_text(contents)
    other_file.write_text(
        'static int private_twice(int n) { return 3*n; }\n'
        '#if 1\n'
        'int other_public(int n) { return private_twice(n); }\n'
        '#else\nint other_public(int n) { return n; }\n#endif\n')
    session = Session(public_root)
    try:
        session.load(public_file)
        session.value("public_answer(18)", 42)
        session.value("public_meta(18)", 42)
        session.run(":symbols private_\n:info public_answer")
        for hidden in ("private_twice", "private_later", "private_meta",
                       "public_prototype", "public_dependency"):
            session.run(":info " + hidden, "not a session function")
            session.run(hidden + "(1);", "unresolved identifier")
        session.run("Func public_saved=public_answer;\n"
                    "int public_through(int n) { return public_answer(n); }")
        session.load(other_file)
        session.value("other_public(7)", 21)
        # Changing private bodies is unrestricted and reaches existing calls.
        public_file.write_text(contents.replace("return 2*n", "return 4*n"))
        session.load(public_file)
        session.value("public_saved(18)", 84)
        session.value("public_through(18)", 84)
        session.value("other_public(7)", 21)
        output = session.finish()
        assert 'loaded ("other_public")' in output, output
        assert "int public_answer(int);" in output, output
        assert all(f'"{name}"' not in output for name in
                   ("private_twice", "private_later", "private_meta",
                    "public_prototype", "public_dependency")), output
    finally:
        session.close()

# Ordinary adapters preserve the existing independent-data boundary.
crossing_root = root / "crossing"
crossing_root.mkdir()
crossing_file = crossing_root / "crossing.x"
crossing_file.write_text(
    "typedef struct LoadedRecord { int n; } LoadedRecord;\n"
    "LoadedRecord loaded_record(void) { LoadedRecord r={42}; return r; }\n"
    "int loaded_record_value(void) { return loaded_record().n; }\n"
    "static int value=3;\n"
    "int *loaded_pointer(void) { return &value; }\n"
    "int loaded_deref(int *p) { return *p; }\n"
    "int loaded_ref(int &n) { n++; return n; }\n")
session = Session(crossing_root)
try:
    session.load(crossing_file)
    session.value("loaded_record_value()", 42)
    session.run("loaded_record();", "evaluation failed: loaded_record failed: "
                "record values cannot cross the helper boundary\n")
    session.run("int kept=7;")
    session.run("loaded_pointer();",
                "evaluation failed: loaded_pointer failed: "
                "native pointers cannot cross the helper boundary\n")
    session.run("loaded_deref(&kept);", "arguments must be independent data values")
    session.run("loaded_ref(kept);", "want value")
    session.value("kept", 7)
    session.finish()
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
        session.load(types_file, "declaration changed")
        session.value("p.x", 8)
    split = ("typedef struct { int x; int y; } Point;\n"
             "typedef struct { int x; int y; } Same;\n")
    types_file.write_text(extra + split + ping)
    session.load(types_file, "declaration changed")
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

# An ordinary C entry owns native state and can print without a newline.
main_root = root / "main"
main_root.mkdir()
program = main_root / "program.c"
original_main = (
    '#include <stdio.h>\n'
    'static int calls;\n'
    'static int _original_main(void) { return 40; }\n'
    'int main() {\n'
    '  calls++; printf("out%d", calls); fprintf(stderr, "err%d", calls);\n'
    '  return _original_main() + calls;\n'
    '}\n')
program.write_text(original_main)
session = Session(main_root)
try:
    session.load(program)
    assert "out1" not in session.output.read_text()
    session.run("main();", "err1")
    assert "out1=> 41\n" in session.output.read_text()
    session.run("main();", "err2")
    assert "out2=> 42\n" in session.output.read_text()
    session.run(":info main")
    assert program.read_text() == original_main
    program.write_text(
        '#include <stdio.h>\nint main(void) { '
        'printf("out-fail"); fprintf(stderr, "err-fail"); '
        'raise %(bad-arg (message "main failed")); }\n')
    session.load(program)
    session.run("main();", "err-fail")
    assert session.output.read_text().endswith("out-fail")
    output = session.finish()
    assert "int main(void);" in output, output
finally:
    session.close()

# argc/argv uses the normal stable adapter, including its reload checks.
dependency = main_root / "program.h"
program = main_root / "program.x"
second = main_root / "second.x"
dependency.write_text("static int offset(void) { return 100; }\n")
second.write_text('#include "program.h"\n'
                  'meta int other_offset(void) { return offset(); }\n')


def main_version(parameters="int argc, char *argv[]", body=None):
    if body is None:
        body = ("if (argv[argc] != 0) return -1; "
                "for (int i=0; i<argc; i++) { "
                "if (!argv[i]) return -2; "
                "if (argv[i][0]) argv[i][0]='X'; } "
                "return offset() + argc + ++calls;")
    return ('#include "program.h"\nstatic int calls;\n'
            'meta int main_calls(void) { return calls; }\n'
            f'int main({parameters}) {{ {body} }}\n')


program.write_text(main_version())
session = Session(main_root)
try:
    session.run('int prompt_marker=7;\nArray args=["program", ""];')
    session.load(program)
    session.load(second)
    session.run('Func saved_main=main;\n'
                'int through_main(Array a) { return main(a)+prompt_marker; }')
    session.value('main(args)', 103)
    session.value('args[0]', '"program"')
    session.value('saved_main(args)', 104)
    session.value('through_main(["program"])', 111)
    session.value('main([])', 104)
    session.value('main_calls()', 4)
    session.run(':info main')
    dependency.write_text("static int offset(void) { return 200; }\n")
    program.write_text(main_version("int count, char **values").replace(
        "argv", "values").replace("argc", "count"))
    session.load(program)
    session.value('main_calls()', 0)
    session.value('saved_main(args)', 203)
    session.value('through_main(["program"])', 210)
    session.value('other_offset()', 200)
    session.value('prompt_marker', 7)
    for changed, error in [
            (main_version() + 'broken {', 'expected'),
            (main_version('void', 'return 9;'), 'function type changed: main'),
            ('meta int main_calls(void) { return 99; }\n',
             'main is ')]:
        program.write_text(changed)
        session.load(program, error)
        session.value('main_calls()', 2)
    conflict = main_root / 'conflict.c'
    conflict.write_text('int main(int n, char **v) { return n; }\n')
    program.write_text(main_version())
    session.load(conflict, True)
    session.value('saved_main(args)', 205)
    output = session.finish()
    assert 'int main(Array);' in output, output
    assert 'reloaded ("main_calls" "main")' in output, output
finally:
    session.close()

# Native references keep the original signature. Both ordinary and explicit
# meta definitions work, and a renamed main retains C's implicit return zero.
for name, text, expression, expected in [
        ('recursive.c', 'int main(void) { static int calls; calls++; '
         'int (*again)(void)=main; return calls<3 ? again() : calls; }',
         'main()', 3),
        ('fallthrough.c', 'int main() {}', 'main()', 0),
        ('fallthrough.x', 'int main() {}', 'main()', 0),
        ('alias.c', 'typedef int Count; typedef char **Args; '
         'Count main(Count n, Args v) { return n + (v[n]==0); }',
         'main(["p"])', 2),
        ('meta.x', 'meta int main(int n, char **v) { return n; }',
         'main(["p"])', 1)]:
    program = main_root / name
    program.write_text(text)
    session = Session(main_root)
    try:
        session.load(program)
        session.value(expression, expected)
        session.finish()
        assert program.read_text() == text
    finally:
        session.close()

# Public scalar objects share native storage and keep their bindings on reload.
scalar_root = root / "scalars"
scalar_root.mkdir()
scalars = scalar_root / "globals.x"
scalar_dependency = scalar_root / "dependency.x"
scalar_dependency.write_text("int dependency_value = 4;\n")


def scalar_version(initial=10, declaration="int counter", extra=""):
    return ('#include <stdbool.h>\n#include "dependency.x"\n'
            f'{declaration} = {initial};\n'
            'typedef const int Limit;\nLimit limit = 100;\n'
            'static int secret = 9;\n'
            'bool enabled = 1;\nunsigned char small = 250;\n'
            'double fraction = 1.25;\nvolatile int observed = 2;\n'
            'enum Color { RED = 3 };\nenum Color color = RED;\n'
            'String label = "start";\nSymbol mark = <start>;\n'
            'int *pointer;\nArray collection;\n'
            'int read_counter(void) { return counter; }\n'
            'void write_counter(int n) { counter = n; }\n'
            'int dep_value(void) { return dependency_value; }\n' + extra)


scalars.write_text(scalar_version())
session = Session(scalar_root)
try:
    session.run('int prompt_data=7;')
    session.load(scalars)
    session.value('counter', 10)
    session.run('counter = 20;')
    session.value('read_counter()', 20)
    session.run('write_counter(30);')
    session.value('counter', 30)
    session.value('(counter = 32)', 32)
    session.value('(counter++)', 32)
    session.value('(++counter)', 34)
    session.value('(counter *= 2)', 68)
    session.run('int bump(int n) { counter += n; return counter++; }\n'
                'Func saved_bump = bump;\n'
                'int shadow(int counter) { return counter + 2; }')
    session.value('bump(5)', 73)
    session.value('counter', 74)
    session.value('shadow(4)', 6)
    session.run('Func identity = %!(int n) => n;')
    session.value('identity(counter)', 74)
    session.run('int through_value(void) { return identity(counter); }')
    session.value('through_value()', 74)
    session.value('limit', 100)
    for statement in ['limit = 2;', 'limit++;',
                      'int change_limit(void) { return limit = 2; }']:
        session.run(statement, 'loaded const global is read-only')
    for name in ['secret', 'dependency_value', 'pointer', 'collection']:
        session.run(name + ';', 'unresolved identifier: ' + name)
    session.run('enabled = 7;\nsmall = 257;\nfraction += 0.5;\n'
                'color = 5;\nlabel = "changed";\nmark = <changed>;')
    session.value('enabled == 1 && small == 1 && fraction == 1.75', 1)
    session.value('(int) color', 5)
    session.value('label', '"changed"')
    session.value('mark', '<changed>')
    session.run('&counter;', 'loaded globals cannot supply addresses')
    session.run('int by_ref(int &n) { n=1; return n; }')
    session.run('by_ref(counter);', 'loaded globals cannot supply addresses')
    session.run('int remote_ref(void) { return by_ref(counter); }',
                'loaded globals cannot supply addresses')
    session.run('Func saved_ref = by_ref;')
    session.run('saved_ref(counter);', 'evaluation failed')
    session.value('counter', 74)
    session.run('int optional(int &?n) { if (n) return n; return -1; }\n'
                'Func optional_ref = optional;')
    session.run('optional_ref(counter);', 'evaluation failed')
    session.run('int shadow_ref(int (*FuncArg_reference)(int *, int)) '
                '{ return FuncArg_reference(&counter, 7); }',
                'loaded globals cannot supply addresses')
    session.run('int destructure(void) { int local=0; '
                '(counter, local) = %(41 2); return counter + local; }')
    session.value('destructure()', 43)
    session.value('counter', 41)
    session.run('observed = 3;')
    session.value('(observed++)', 3)
    session.value('(--observed)', 3)
    session.value('observed', 3)
    session.value('sizeof counter == sizeof(int)', 1)
    session.value('counter', 41)
    alias = scalar_root / 'alias.x'
    alias.symlink_to(scalars)
    scalar_dependency.write_text('int dependency_value = 9;\n')
    scalars.write_text(scalar_version(40, extra='int added = 6;\n'))
    session.load(alias)
    session.value('counter', 40)
    session.value('saved_bump(2)', 42)
    session.value('counter', 43)
    session.value('through_value()', 43)
    session.value('prompt_data', 7)
    session.value('dep_value()', 9)
    session.value('added', 6)
    session.value('label', '"start"')
    session.value('small == 250', 1)
    for declaration, error in [
            ('long counter', 'declaration changed'),
            ('const int counter', 'declaration changed'),
            ('static int counter', 'counter is used by prompt function ')]:
        changed = scalar_version(90, declaration, 'int added=6;')
        scalars.write_text(changed.replace('counter = n;', '(void) n;'))
        session.load(scalars, error)
        session.value('counter', 43)
        session.value('read_counter()', 43)
    scalars.write_text(scalar_version() + 'broken {')
    session.load(scalars, 'expected')
    session.value('counter', 43)
    session.run(':symbols counter')
    output = session.finish()
    assert '%((global "counter"))' in output, output
finally:
    session.close()

# Globals-only C files load without annotations, including tentative and
# repeated declarations. A successful load resets the entire native program.
for suffix in ['x', 'c']:
    scalars = scalar_root / ('only.' + suffix)
    scalars.write_text('extern int count;\nint count=3;\nint count;\n'
                       'const int maximum=8;\nstatic int hidden=4;\n'
                       'int items[2]={1,2};\nstruct Entry { int v; } item={3};\n')
    second = scalar_root / ('other.' + suffix)
    second.write_text('int other=11;\n')
    session = Session(scalar_root)
    try:
        session.load(scalars)
        session.load(second)
        session.run('count = 7;\nother = 12;')
        session.value('count', 7)
        session.value('maximum', 8)
        session.run('items[1]=7;\nitem.v=9;')
        session.value('items[1]+item.v', 16)
        session.run('maximum = 1;', 'loaded const global is read-only')
        session.run('hidden;', 'unresolved identifier: hidden')
        session.load(scalars)
        session.value('count', 3)
        session.value('other', 11)
        session.value('items[1]+item.v', 5)
        session.finish()
    finally:
        session.close()

# Aggregate access stays in native storage; inspection returns data snapshots.
aggregate_root = root / 'aggregates'
aggregate_root.mkdir()
aggregates = aggregate_root / 'objects.x'


def aggregate_version(initial=10, size=3, field='int x;', extra=''):
    return (f'typedef struct Point {{ {field} const int fixed; }} Point;\n'
            f'int samples[{size}] = {{{initial}, 20, 30}};\n'
            'Point point = {1, 2};\n'
            'Point points[2] = {{3, 4}, {5, 6}};\n'
            'int matrix[2][2] = {{1, 2}, {3, 4}};\n'
            'typedef const int Row[2];\nRow locked = {7, 8};\n'
            'typedef const Point Frozen;\nFrozen frozen = {9, 10};\n'
            'struct Flex { int size; int tail[]; } flexible = {0};\n'
            'struct Bits { unsigned bits:3; struct { int nested; }; } bits = {2,{3}};\n'
            'union Choice { int n; double f; };\n'
            'struct HasUnion { int n; union Choice choice; } tagged = {4,{5}};\n'
            'static Point secret = {11, 12};\n'
            'static Var private_value = void;\n'
            'int inferred[] = {13, 14};\n'
            'int incomplete[];\n'
            'struct Mixed { int number; int *pointer; } mixed = {15, 0};\n'
            'struct Holder { Point nested; int values[2]; };\n'
            'struct Holder holder={{17,18},{19,20}};\n'
            'const struct Holder fixed_holder={{21,22},{23,24}};\n'
            'int large[1000];\n'
            'int index_calls=0;\nint rhs_calls=0;\n'
            'int next_index(void) { index_calls++; return 1; }\n'
            'double half(void) { rhs_calls++; return 0.5; }\n'
            'int read_sample(int i) { return samples[i]; }\n'
            'int read_point(void) { return point.x; }\n' + extra)


aggregates.write_text(aggregate_version())
session = Session(aggregate_root)
try:
    session.run('int prompt_kept=42;')
    session.load(aggregates)
    session.value('samples[1]', 20)
    session.run('samples[1] = 99;\npoint.x = 7;\npoints[1].x = 8;')
    session.value('read_sample(1)', 99)
    session.value('read_point()', 7)
    session.value('points[1].x', 8)
    session.run('samples[next_index()] *= half();')
    session.value('samples[1]', 49)
    session.value('index_calls == 1 && rhs_calls == 1', 1)
    session.value('(++samples[next_index()])', 50)
    session.value('index_calls', 2)
    session.value('(samples[next_index()]++)', 50)
    session.value('index_calls', 3)
    session.run('matrix[next_index()][next_index()] += 5;')
    session.value('matrix[1][1]', 9)
    session.value('index_calls', 5)
    session.run('int bump_point(int n) { points[1].x += n; '
                'return ++samples[next_index()]; }\n'
                'Func saved_aggregate = bump_point;')
    session.value('bump_point(2)', 52)
    session.value('points[1].x', 10)
    session.value('index_calls', 6)
    session.value('inferred[1]', 14)
    session.value('mixed.number', 15)
    session.value('flexible.size', 0)
    session.value('bits.bits', '2u')
    session.run('bits.bits=5;\nbits.nested=6;')
    session.value('bits.bits', '5u')
    session.value('bits.nested', 6)
    session.value('tagged.n', 4)
    session.run('holder.nested.x=25;\nholder.values[1]+=6;')
    session.value('holder.nested.x + holder.values[1]', 51)
    session.value('fixed_holder.values[1]', 24)
    session.run('flexible.tail[0];', 'loaded field cannot cross')
    session.run('tagged.choice.n;', 'loaded field cannot cross')
    session.value('locked[1]', 8)
    session.value('frozen.x', 9)
    for expression in ['point.fixed=0;', 'points[1].fixed++;',
                       'locked[0]=0;', 'frozen.x=0;',
                       'fixed_holder.values[0]=0;',
                       'int forbidden(void) { return frozen.x++; }']:
        session.run(expression, 'loaded const global is read-only')
    session.run('secret.x;', 'unresolved identifier: secret')
    session.run('incomplete;', 'unresolved identifier: incomplete')
    session.run('mixed.pointer;', 'loaded field cannot cross')
    for expression in ['samples[-1];', 'samples[3]=0;', 'matrix[0][2];']:
        session.run(expression, 'loaded array index out of bounds')
    for expression in ['samples[1.5];', 'samples[1.5]=0;',
                       'int bad_index(void) { return samples[1.5]; }']:
        session.run(expression, 'loaded array indices must be integers')
    session.value('samples[1]', 52)
    session.run('&point.x;', 'loaded globals cannot supply addresses')
    session.run('int ref_element(int &n) { return n; }')
    session.run('ref_element(samples[0]);', 'loaded globals cannot supply')
    session.run('int *escaped = samples;', 'loaded aggregates support')
    session.run('Point copied = point;', 'loaded aggregates support')
    session.run('int takes_point(Point p) { return p.x; }')
    session.run('takes_point(point);', 'loaded aggregates support')
    session.run('int takes_array(int *p) { return p[0]; }')
    session.run('takes_array(samples);', 'loaded aggregates support')
    session.value('samples', '[ 10, 52, 30 ]')
    session.value('matrix[0]', '[ 1, 2 ]')
    session.snapshot('point', {'x': 7, 'fixed': 2})
    session.snapshot('points', [{'x': 3, 'fixed': 4}, {'x': 10, 'fixed': 6}])
    session.snapshot('mixed', {'number': 15, 'pointer': '<unavailable>'})
    session.snapshot('flexible', {'size': 0, 'tail': '<unavailable>'})
    session.snapshot('holder', {'nested': {'x': 25, 'fixed': 18},
                                'values': [19, 26]})
    session.snapshot('large', [0] * 100 + ['...'])
    aggregates.write_text(aggregate_version(40, extra='int added_array[2]={6,7};\n'))
    session.load(aggregates)
    session.value('samples[0]', 40)
    session.value('saved_aggregate(3)', 21)
    session.value('points[1].x', 8)
    session.value('prompt_kept', 42)
    session.value('added_array[1]', 7)
    for changed in [aggregate_version(90, size=4),
                    aggregate_version(90, field='long x;')]:
        aggregates.write_text(changed)
        session.load(aggregates, 'declaration changed')
        session.value('samples[1]', 21)
        session.value('points[1].x', 8)
        session.value('index_calls', 1)
    aggregates.write_text(aggregate_version() + 'broken {')
    session.load(aggregates, 'expected')
    session.value('samples[1]', 21)
    session.value('points[1].x', 8)
    session.finish()
finally:
    session.close()

# Loaded roots link through ordinary prototypes and extern declarations.
# Object arguments select storage inside their one shared native program.
shared_root = root / 'shared'
shared_root.mkdir()
shared_header = shared_root / 'objects.h'
shared_objects = shared_root / 'objects.x'
shared_operations = shared_root / 'operations.x'
shared_dependency = shared_root / 'dependency.x'
shared_header.write_text(
    '#pragma once\n'
    'struct SharedPoint { int x; int y; };\n'
    'struct SharedHolder { struct SharedPoint point; int values[2]; };\n'
    'extern int shared_samples[3];\n'
    'extern struct SharedPoint shared_point;\n'
    'int shared_first(void);\n')


def shared_dependency_version(initial=4):
    return ('#pragma once\n'
            f'int shared_dependency = {initial};\n'
            'int dependency_next(void) { return ++shared_dependency; }\n')


def shared_object_version(initial=10):
    return ('#pragma once\n#include "objects.h"\n#include "dependency.x"\n'
            f'int shared_samples[3] = {{{initial},20,30}};\n'
            'struct SharedPoint shared_point = {1,2};\n'
            'struct SharedPoint shared_points[2] = {{3,4},{5,6}};\n'
            'struct SharedHolder shared_holder = {{5,6},{7,8}};\n'
            'const struct SharedPoint shared_frozen = {9,10};\n'
            'const int shared_locked[2] = {11,12};\n'
            'static int private_shared = 40;\n'
            'int shared_first(void) { return shared_samples[0]; }\n'
            'int shared_head(const int values[3], const int n) { '
            'return values[n]; }\n'
            'int objects_next(void) { return dependency_next(); }\n')


shared_operation_text = (
    '#include "objects.h"\n#include "dependency.x"\n#include <stdlib.h>\n'
    'int shared_head(const int *values, int n);\n'
    'int shared_pick(void) { return shared_head(shared_samples,1); }\n'
    'static int private_shared = 2;\n'
    'int shared_calls;\n'
    'int shared_sum(const int *values, int count) { '
    'shared_calls++; int sum=0; for (int i=0; i<count; i++) sum+=values[i]; '
    'return sum; }\n'
    'void shared_shift(struct SharedPoint *p, int dx) { p->x+=dx; }\n'
    'int shared_copy(struct SharedPoint p) { p.x+=100; return p.x+p.y; }\n'
    'int shared_reference(struct SharedPoint &p, int dx) { '
    'p.x+=dx; return p.x; }\n'
    'int shared_alias(int *a, int *b) { *a+=2; *b+=3; return *a+*b; }\n'
    'int shared_pair(const int *p, int n) { return *p*100+n; }\n'
    'int shared_array(const int p[3]) { return p[2]; }\n'
    'int shared_const_pointer(int *const p) { return p[0]; }\n'
    'int shared_advance(void) { shared_samples[0]+=private_shared; '
    'return shared_first(); }\n'
    'int operations_next(void) { return dependency_next(); }\n'
    'int *shared_address(void) { return shared_samples; }\n'
    'struct SharedPoint shared_result(void) { return shared_point; }\n'
    'void shared_exit(void) { exit(6); }\n')
shared_dependency.write_text(shared_dependency_version())
shared_objects.write_text(shared_object_version())
shared_operations.write_text(shared_operation_text)
session = Session(shared_root)
try:
    session.run('int shared_prompt=7;')
    session.load(shared_objects)
    session.run('Func shared_saved=shared_first;\n'
                'int shared_before(void) { return shared_first()+shared_prompt; }')
    session.run('shared_samples[0]=99;')
    session.load(shared_operations)
    session.value('shared_before()', 17)
    session.value('shared_saved()', 10)
    session.value('shared_sum(shared_samples,3)', 60)
    session.value('shared_array(shared_samples)', 30)
    session.value('shared_const_pointer(shared_samples)', 10)
    session.value('shared_pick()', 20)
    session.run('int shared_through(void) { '
                'shared_shift(&shared_holder.point,1); '
                'return shared_sum(shared_holder.values,2)+shared_prompt; }')
    session.value('shared_through()', 22)
    session.value('shared_holder.point.x', 6)
    session.value('shared_copy(shared_point)', 103)
    session.value('(shared_copy)(shared_point)', 103)
    session.value('shared_point.x', 1)
    session.run('shared_shift(&shared_point,5);')
    session.value('shared_reference(shared_point,2)', 8)
    session.value('shared_point.x', 8)
    session.value('shared_copy(shared_points[1])', 111)
    session.value('shared_sum(shared_locked,2)', 23)
    session.value('shared_copy(shared_frozen)', 119)
    session.value('shared_alias(&shared_samples[0],&shared_samples[0])', 30)
    session.value('shared_samples[0]', 15)
    session.value('shared_advance()', 17)
    session.value('shared_saved()', 17)

    # Both the selector and the later scalar argument run exactly once.
    session.run('int shared_index=0;\n'
                'int shared_next(void) { return shared_index++; }')
    session.value('shared_pair(&shared_samples[shared_next()],shared_next())',
                  1701)
    session.value('shared_index', 2)
    session.run('shared_index=0;')
    session.value('shared_alias(&shared_samples[shared_next()],'
                  '&shared_samples[shared_next()])', 42)
    session.value('shared_index', 2)
    session.value('shared_samples[0]', 19)
    session.value('shared_samples[1]', 23)
    session.run('int shared_once(void) { shared_index=0; '
                'return shared_pair(&shared_samples[shared_index++],'
                'shared_index++); }')
    session.value('shared_once()', 1901)
    session.value('shared_index', 2)

    for expression in ['shared_shift(&shared_frozen,1);',
                       'shared_alias(&shared_locked[0],&shared_samples[0]);',
                       'shared_reference(shared_frozen,1);',
                       'shared_copy(shared_holder);',
                       'shared_copy(shared_points);',
                       'shared_shift(&shared_samples[0],1);']:
        session.run(expression, True)
    for expression in ['shared_sum(&shared_samples[3],1);',
                       'shared_copy(shared_points[-1]);',
                       'shared_sum(&shared_holder.values[2],1);']:
        session.run(expression, 'loaded array index out of bounds')
    session.run('shared_sum(&shared_samples[1.5],1);',
                'loaded array indices must be integers')
    session.value('shared_calls', 3)
    session.value('shared_samples[0]', 19)
    session.value('shared_frozen.x', 9)
    session.run('private_shared;', 'unresolved identifier')
    session.run('shared_dependency;', 'unresolved identifier')
    session.run('shared_address();',
                'native pointers cannot cross the helper boundary')
    session.run('shared_result();',
                'record values cannot cross the helper boundary')
    session.run('int shared_local=21;')
    session.run('shared_sum(&shared_local,1);',
                'arguments must be independent data values')
    session.value('shared_local', 21)

    session.value('objects_next()', 5)
    session.value('operations_next()', 6)
    # Exposing an already included source keeps one definition and resets it.
    session.load(shared_dependency)
    session.value('shared_dependency', 4)
    session.value('shared_calls', 0)
    session.value('shared_saved()', 10)
    session.value('objects_next()', 5)
    session.value('operations_next()', 6)
    session.value('shared_dependency', 6)
    session.value('dependency_next()', 7)
    session.run('shared_dependency=20;\nshared_samples[0]=40;')
    session.value('objects_next()', 21)
    session.value('shared_sum(shared_samples,3)', 90)

    # Loading one root validates current edits to every registered root.
    shared_operations.write_text(shared_operation_text + 'broken {')
    session.load(shared_objects, 'expected')
    session.value('shared_saved()', 40)
    session.value('shared_calls', 1)
    session.value('operations_next()', 22)
    shared_operations.write_text(shared_operation_text.replace(
        'int shared_advance(void)', 'long shared_advance(void)'))
    session.load(shared_objects, 'function type changed')
    session.value('shared_calls', 1)
    session.value('shared_dependency', 22)
    session.value('shared_before()', 47)

    shared_operations.write_text(shared_operation_text)
    shared_dependency.write_text(shared_dependency_version(30))
    shared_objects.write_text(shared_object_version(50))
    session.load(shared_objects)
    session.value('shared_calls', 0)
    session.value('shared_saved()', 50)
    session.value('shared_before()', 57)
    session.value('shared_through()', 22)
    session.value('shared_holder.point.x', 6)
    session.value('objects_next()', 31)
    session.value('operations_next()', 32)
    session.value('shared_dependency', 32)
    session.value('shared_prompt', 7)
    session.value('shared_index', 2)
    session.run('shared_exit();', 'the body exited with status 6')
    session.value('shared_dependency', 30)
    session.value('shared_calls', 0)
    session.value('shared_holder.point.x', 5)
    session.value('shared_saved()', 50)
    session.finish()
finally:
    session.close()

# A reload may remove a function that no prompt code refers to. The name
# leaves the session, and a later version may define it again.
removal_root = root / "removal"
removal_root.mkdir()
removal = removal_root / "removal.x"
kept = "int removal_kept(int n) { return n + 1; }\n"
helper = "int removal_helper(int n) { return n * 2; }\n"
other = "int removal_other(int n) { return n; }\n"
removal.write_text(kept + helper)
session = Session(removal_root)
try:
    session.load(removal)
    session.value("removal_helper(4)", 8)
    removal.write_text(kept)
    session.load(removal)
    session.run("removal_helper(4);", "unresolved identifier: removal_helper")
    session.run(":info removal_helper", "not a session function")
    session.run(":symbols removal_")
    session.value("removal_kept(4)", 5)
    removal.write_text(kept + helper.replace("n * 2", "n * 3") + other)
    session.load(removal)
    session.value("removal_helper(4)", 12)
    session.run("int plus_helper(int n) { return removal_helper(n) + 1; }\n"
                "Func saved_other = removal_other;")
    removal.write_text(kept + other)
    session.load(removal, "removal_helper is called by prompt function "
                 "plus_helper")
    removal.write_text(kept + helper)
    session.load(removal, "removal_other is saved in prompt variable "
                 "saved_other")
    session.value("plus_helper(4)", 13)
    session.value("saved_other(4)", 4)

    # Types and globals follow the same rule.
    current = kept + helper.replace("n * 2", "n * 3") + other
    box = ("typedef struct Box { int v; } Box;\nint box_count = 2;\n"
           "int box_value(Box b) { return b.v; }\n")
    removal.write_text(current + box)
    session.load(removal)
    session.value("box_count", 2)
    removal.write_text(current)
    session.load(removal)
    session.run("box_count;", "unresolved identifier: box_count")
    removal.write_text(current + box)
    session.load(removal)
    session.run("int uses_count(void) { return box_count; }\n"
                "int uses_box(Box b) { return b.v; }")
    removal.write_text(current + box.replace("int box_count = 2;\n", ""))
    session.load(removal, "box_count is used by prompt function uses_count")
    removal.write_text(current)
    session.load(removal, "is used by prompt function uses_")
    session.value("uses_count()", 2)
    output = session.finish()
    assert f'removed ("removal_helper") from {removal}' in output, output
    assert (f'removed ("Box" "box_count" "box_value") from {removal}'
            in output), output
    assert '%((native "removal_kept"))' in output, output
    assert output.count("reloaded (") == 5, output
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
