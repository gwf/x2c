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
        require(re.search(r"=> (?:\w+ )?" + str(number) + r"\n", output),
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
        repl.check(":inspect packet", "marker: 7", "value: 1234")
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


with tempfile.TemporaryDirectory(prefix="x2c-repl-playground-") as temporary:
    directory = Path(temporary)
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
            repl.check(":symbols sqlite3_open", "sqlite3_open")
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
