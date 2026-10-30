#!/usr/bin/env python3
"""Create, call, and inspect ordinary C libraries through the public command."""
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
BINARY = Path(sys.argv[1] if len(sys.argv) > 1 else
              ROOT / "builds/0/libexec/x2c-repl").resolve()
TIMEOUT = 90


def require(condition, evidence):
    if not condition:
        raise AssertionError(evidence)


class Playground:
    def __init__(self, arguments, directory):
        self.process = subprocess.Popen(
            [str(BINARY), *map(str, arguments)], cwd=ROOT,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=dict(os.environ, XDG_STATE_HOME=str(directory / "state")))
        self.output = b""
        self.errors = b""
        self.sequence = 0

    def command(self, source):
        self.sequence += 1
        token = f"__playground_sync_{self.sequence}__".encode()
        start, errors = len(self.output), len(self.errors)
        self.process.stdin.write(source.encode() + b"\n" +
                                 b'print("' + token + b'\\n");\n')
        self.process.stdin.flush()
        end = time.monotonic() + TIMEOUT
        while time.monotonic() < end:
            if token in self.output[start:]:
                return (self.output[start:].decode(errors="replace"),
                        self.errors[errors:].decode(errors="replace"))
            streams = select.select(
                [self.process.stdout, self.process.stderr], [], [], .1)[0]
            for stream in streams:
                chunk = os.read(stream.fileno(), 65536)
                if not chunk:
                    raise AssertionError((self.output.decode(errors="replace"),
                                          self.errors.decode(errors="replace")))
                if stream is self.process.stdout:
                    self.output += chunk
                else:
                    self.errors += chunk
        raise AssertionError((source, self.output.decode(errors="replace"),
                              self.errors.decode(errors="replace")))

    def check(self, source, *expected):
        output, errors = self.command(source)
        require(not errors and all(text in output for text in expected),
                (source, expected, output, errors))
        return output

    def value(self, expression, number):
        output = self.check(expression + ";")
        require(re.search(r"=> (?:[^\n]* )?" + str(number) + r"[uUlL]*\n", output),
                (expression, number, output))

    def close(self, expected=0):
        if self.process.poll() is None:
            output, errors = self.process.communicate(b":quit\n", timeout=TIMEOUT)
            self.output += output
            self.errors += errors
        require(self.process.returncode == expected,
                (self.process.returncode, self.output.decode(errors="replace"),
                 self.errors.decode(errors="replace")))


def workflow(arguments, directory, implementation):
    repl = Playground(arguments, directory)
    try:
        repl.check(":symbols playground", "playground_new", "playground_move")
        repl.check(":info playground_new", "int x", "int y")
        source = repl.check(":source playground_new", "playground_new")
        require(("malloc" in source) == implementation, source)
        repl.check(":members PlaygroundPoint", "int x", "playground_move")
        repl.check("PlaygroundPoint *p=playground_new(1,2);", "ok")
        repl.check("PlaygroundPoint *alias=p;", "ok")
        repl.check("playground_move(p,5);", "ok")
        repl.check(":inspect *alias", "x: 6", "y: 2")
        repl.check("PlaygroundPoint copy=playground_value(8,9);", "ok")
        repl.check("playground_move(&copy,2);", "ok")
        repl.check(":inspect copy", "x: 10", "y: 9")
        repl.check("PlaygroundPacket packet=playground_packet(7,1234);", "ok")
        repl.check(":inspect packet", "marker:", "value: 1234")
        repl.value("packet.marker==7", 1)
        repl.value("sizeof(PlaygroundPacket)==5", 1)
        repl.value("PLAYGROUND_SCALE", 3)
        repl.value("PLAYGROUND_Y", 2)
        repl.check("int bias=1;", "ok")
        repl.check("int combine(int x,int y) { return x*10+y+bias; }",
                   "defined combine")
        repl.value("playground_apply(p,combine)", 63)
        repl.check("bias=2;", "ok")
        repl.value("playground_apply(p,combine)", 64)
        repl.check("PlaygroundHandle *handle=playground_open(42);", "ok")
        repl.value("playground_read(handle)", 42)
        repl.check(":members handle", "playground_read", "playground_close")
        repl.check("playground_calls=17;", "ok")
        repl.value("playground_calls", 17)
        repl.check("playground_close(handle);", "ok")
        repl.check("playground_free(p); p=NULL; alias=NULL;", "ok")
    finally:
        repl.close()


def source_statics(directory):
    header = directory / "private-header.h"
    header.write_text("""static int included_counter = 71;
static inline int included_read(void) { return included_counter; }
""")
    source = directory / "private.c"
    original = """#include "private-header.h"
struct Counter { int value; };
static struct Counter counter = {3};
static int samples[3] = {2, 4, 6};
static const int fixed = 9;
static volatile int watched = 7;
static int bump(int amount) {
  static int calls;
  counter.value += amount;
  return ++calls;
}
static inline int total(void) { return counter.value + samples[1]; }
int public_read(void) {
  return counter.value + samples[1] + fixed + watched + included_read();
}
int public_bump(int amount) { return bump(amount); }
"""
    source.write_text(original)
    other = directory / "other.c"
    other.write_text("static struct Other { double value; } counter = {99};\n")
    repl = Playground([source, source], directory)
    expected_status = 0
    try:
        repl.check(":symbols bump", "bump", str(source))
        repl.check(":source bump", "static int bump", "static int calls;")
        repl.check(":source counter", "counter = {3}")
        repl.check(":inspect counter", "value: 3")
        repl.check(":inspect samples", "[ 2, 4, 6 ]")
        repl.value("public_read()", 94)
        repl.value("bump(5)", 1)
        repl.value("public_bump(2)", 2)
        repl.check(":inspect counter", "value: 10")
        repl.check("counter.value=20; samples[1]=10;", "ok")
        repl.value("public_read()", 117)
        repl.value("total()", 30)
        repl.check(":info fixed", "const int")
        repl.check(":info watched", "volatile int")
        require("included_read" not in repl.check(":symbols included_read"),
                repl.output.decode())
        require("included_counter" not in repl.check(":symbols included_counter"),
                repl.output.decode())
        output, errors = repl.command(f':load "{other}"')
        expected_status = 1
        require("ambiguous file-local name counter" in errors
                and str(source.resolve()) in errors
                and str(other.resolve()) in errors,
                (output, errors))
        repl.value("counter.value", 20)
        repl.value("bump(1)", 3)
        source.write_text(original.replace("counter = {3}", "counter = {40}"))
        repl.check(":source counter", "counter = {3}")
        repl.check(":reload", "started fresh session")
        repl.check(":source counter", "counter = {40}")
        repl.value("counter.value", 40)
        repl.value("bump(1)", 1)
    finally:
        repl.close(expected_status)

    private = directory / "private-function.c"
    private.write_text("static int hidden(int x) { return x+100; }\n"
                       "int call_private(void) { return hidden(2); }\n")
    api = directory / "external-api.h"
    api.write_text("int hidden(int x);\n")
    client = directory / "external-client.c"
    client.write_text('#include "external-api.h"\n'
                      'int call_external(void) { return hidden(2); }\n')
    external = directory / "external.c"
    external.write_text("int hidden(int x) { return x+200; }\n")
    native = directory / "external.o"
    subprocess.run(["cc", "-fPIC", "-c", str(external), "-o", str(native)],
                   check=True)
    for first, second in ((private, client), (client, private)):
        failed = subprocess.run([str(BINARY), str(first), str(second), str(native)],
                                input="", text=True, capture_output=True,
                                cwd=ROOT, timeout=TIMEOUT)
        require(failed.returncode != 0
                and "ambiguous file-local name hidden" in failed.stderr
                and str(first.resolve()) in failed.stderr
                and str(second.resolve()) in failed.stderr,
                (failed.stdout, failed.stderr))
    print("C source statics, shared identity, header privacy and reload passed",
          flush=True)


def nbody(directory):
    source = ROOT / "examples/shootout/benchmarks/nbody/main.c"
    original = source.read_bytes()
    native = directory / "nbody"
    subprocess.run(["cc", str(source), "-lm", "-o", str(native)], check=True)
    expected = subprocess.check_output([str(native), "1"], text=True).splitlines()
    demo = ROOT / "commands/repl/examples/nbody.repl"
    completed = subprocess.run([str(BINARY)], input=demo.read_text(), text=True,
                               capture_output=True, cwd=ROOT, timeout=TIMEOUT,
                               env=dict(os.environ,
                                        XDG_STATE_HOME=str(directory / "state")))
    output = completed.stdout
    require(completed.returncode == 0 and not completed.stderr,
            (output, completed.stderr))
    for declaration in ("static void advance", "static double energy",
                        "static void offset_momentum"):
        require(re.search(r"^function +" + declaration, output, re.MULTILINE),
                output)
    require("global    Body bodies[5];" in output
            and "system[0].vx = -px / SOLAR_MASS;" in output
            and "field    double mass;" in output, output)
    bodies = re.findall(r"^=> Body \{ (.*) \}$", output, re.MULTILINE)
    require(len(bodies) == 4, output)
    states = [dict(re.findall(r"(\w+): ([^, }]+)", body)) for body in bodies]
    require(float(states[0]["vx"]) == 0 and float(states[1]["vx"]) != 0
            and states[2]["x"] != states[3]["x"], output)
    require(re.findall(r"^-0\.\d+$", output, re.MULTILINE) == expected, output)
    require(source.read_bytes() == original, "N-body C source changed")
    print("unchanged C N-body discovery, source, calls and inspection passed",
          flush=True)


with tempfile.TemporaryDirectory(prefix="x2c-repl-playground-") as temporary:
    directory = Path(temporary)
    source_statics(directory)
    nbody(directory)
    fixture = ROOT / "commands/repl/tests/library"
    source, header = directory / "playground.c", directory / "playground.h"
    shutil.copyfile(fixture / source.name, source)
    shutil.copyfile(fixture / header.name, header)
    workflow([source], directory, True)
    print("C source create-call-inspect, callbacks, opaque and packed values passed",
          flush=True)

    native = directory / "playground.o"
    archive = directory / "libplayground.a"
    subprocess.run(["cc", "-fPIC", "-c", str(source), "-o", str(native)],
                   check=True)
    subprocess.run(["ar", "rcs", str(archive), str(native)], check=True)
    workflow([header, archive], directory, False)
    print("header plus archive create-call-inspect passed", flush=True)

    repl = Playground([source], directory)
    try:
        repl.check("int prompt_value=91;", "ok")
        original = source.read_text()
        source.write_text(original.replace("point->x += dx", "point->x += dx * 2"))
        header.write_text(header.read_text().replace("PLAYGROUND_SCALE 3",
                                                   "PLAYGROUND_SCALE 99"))
        repl.check(":source playground_move", "point->x += dx;")
        repl.check(":reset", "started fresh session")
        repl.value("PLAYGROUND_SCALE", 3)
        repl.check("PlaygroundPoint p={1,2};", "ok")
        repl.check("playground_move(&p,5);", "ok")
        repl.value("p.x", 6)
        repl.check(":reload", "started fresh session")
        repl.value("PLAYGROUND_SCALE", 99)
        repl.check(":source playground_move", "point->x += dx * 2;")
        repl.check("PlaygroundPoint p={1,2};", "ok")
        repl.check("playground_move(&p,5);", "ok")
        repl.value("p.x", 11)
        repl.value("playground_calls", 0)
        output = repl.check(":symbols prompt_value")
        require("prompt_value" not in output, output)
    finally:
        repl.close()
    print("source snapshots, pinned reset, and explicit reload passed", flush=True)

    extra = directory / "extra.c"
    extra.write_text("""typedef union Choice { int integer; double real; } Choice;
typedef struct Details { unsigned bits:3; volatile int watch; int items[4]; } Details;
int fill_number(int *result) { *result=42; return 0; }
int callback_data(int (*call)(int,void *),void *data) { return call(4,data); }
""")
    repl = Playground([extra], directory)
    try:
        repl.check("int result=0;", "ok")
        repl.value("fill_number(&result)", 0)
        repl.value("result", 42)
        repl.check("int callback(int n,void *p) { return n+*(int *)p; }",
                   "defined callback")
        repl.value("callback_data(callback,&result)", 46)
        repl.check("Details details={5,7,{1,2,3,4}};", "ok")
        repl.check(":inspect details", "bits: 5", "watch: <volatile>",
                   "[ 1, 2, 3, 4 ]")
        repl.value("details.bits", 5)
        repl.value("details.watch", 7)
        repl.check(":inspect --limit 2 details", "...")
        repl.check("Choice choice={.integer=17};", "ok")
        union = repl.check(":inspect choice", "integer", "real")
        require("integer: 17" not in union, union)
        repl.value("choice.integer", 17)
        repl.check("int reads=0;", "ok")
        repl.check("int next(void) { reads++; return 13; }", "defined next")
        repl.check(":info next()", "int")
        repl.value("reads", 0)
        repl.check(":inspect next()", "int 13")
        repl.value("reads", 1)
    finally:
        repl.close()
    print("out-parameters, userdata, bounded display and single evaluation passed",
          flush=True)

    # Query the configured host C installation; never install a dependency.
    available = subprocess.run(["cc", "-E", "-x", "c", "-"],
                               input="#include <sqlite3.h>\n", text=True,
                               capture_output=True)
    if available.returncode:
        print("SQLite walkthrough skipped: host sqlite3.h unavailable", flush=True)
    else:
        sqlite_header = directory / "sqlite-api.h"
        sqlite_header.write_text("#include <sqlite3.h>\n")
        repl = Playground(["-l", "sqlite3", sqlite_header], directory)
        try:
            repl.check(":symbols --all sqlite3_open", "sqlite3_open")
            repl.check("sqlite3 *db=NULL;", "ok")
            repl.value('sqlite3_open(":memory:",&db)', 0)
            repl.check("sqlite3_stmt *query=NULL;", "ok")
            repl.value('sqlite3_prepare_v2(db,"SELECT 6*7",-1,&query,NULL)', 0)
            repl.value("sqlite3_step(query)", 100)
            repl.value("sqlite3_column_int(query,0)", 42)
            repl.value("sqlite3_finalize(query)", 0)
            repl.value("sqlite3_close(db)", 0)
        finally:
            repl.close()
        print("host SQLite open-prepare-step-read-finalize-close passed", flush=True)

    diagnostics = subprocess.run(
        [str(BINARY)], input="1 +;\nint available=3;\navailable;\n",
        text=True, capture_output=True, cwd=ROOT, timeout=TIMEOUT)
    require(diagnostics.returncode == 1 and "<repl>:1:4" in diagnostics.stderr
            and "1 +;" in diagnostics.stderr and "=> int 3" in diagnostics.stdout,
            (diagnostics.stdout, diagnostics.stderr))
    multiline = subprocess.run(
        [str(BINARY)], input="int sum(int x) {\nreturn x+2;\n}\nsum(3);\n",
        text=True, capture_output=True, cwd=ROOT, timeout=TIMEOUT)
    require(multiline.returncode == 0 and "=> int 5" in multiline.stdout,
            (multiline.stdout, multiline.stderr))
    bad_option = subprocess.run([str(BINARY), "--no-such-option"],
                                input="", text=True, capture_output=True,
                                cwd=ROOT, timeout=TIMEOUT)
    require(bad_option.returncode != 0 and "--no-such-option" in bad_option.stderr,
            (bad_option.stdout, bad_option.stderr))
    print("diagnostics, continuation and option errors passed", flush=True)
