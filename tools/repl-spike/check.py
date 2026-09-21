#!/usr/bin/env python3
"""Optional focused checks for the integrated experimental REPL; not a repository gate."""
import os
import pathlib
import pty
import re
import fcntl
import select
import signal
import struct
import tempfile
import statistics
import subprocess
import termios
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
BINARY = pathlib.Path(os.environ.get("X2C", ROOT / "builds/0/x2c")).resolve()
BUILD = ROOT / "unittest/build/repl-spike"
BUILD.mkdir(parents=True, exist_ok=True)



def run(source, *args):
    return subprocess.run([str(BINARY), "repl", *args], input=source,
                          text=True, capture_output=True, cwd=tempfile.gettempdir(), timeout=20)


def check(source, stdout, error="", code=None):
    if code is None:
        code = int(bool(error))
    result = run(source)
    assert result.returncode == code, result
    assert result.stdout == stdout, result
    assert error in result.stderr, result
    if not error:
        assert not result.stderr, result.stderr


class PtyRepl:
    def __init__(self, columns=80, term="xterm-256color"):
        self.master, self.slave = pty.openpty()
        window = struct.pack("HHHH", 24, columns, 0, 0)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, window)
        self.original = termios.tcgetattr(self.slave)
        env = {**os.environ, "TERM": term}
        self.process = subprocess.Popen(
            [str(BINARY), "repl"], stdin=self.slave, stdout=self.slave,
            stderr=self.slave, cwd=tempfile.gettempdir(), env=env,
            start_new_session=True)
        self.output = b""

    def send(self, data):
        start = len(self.output)
        sent = 0
        while sent < len(data):
            sent += os.write(self.master, data[sent:])
        return start

    def expect(self, text, start=0, timeout=20):
        deadline = time.monotonic() + timeout
        while text not in self.output[start:]:
            assert time.monotonic() < deadline, (text, self.output[start:])
            ready, _, _ = select.select([self.master], [], [], 0.2)
            if not ready:
                continue
            try:
                self.output += os.read(self.master, 65536)
            except OSError:
                break
        assert text in self.output[start:], (text, self.output[start:])
        return len(self.output)

    def wait(self, code=0, timeout=20):
        deadline = time.monotonic() + timeout
        while self.process.poll() is None:
            assert time.monotonic() < deadline, self.output
            ready, _, _ = select.select([self.master], [], [], 0.2)
            if ready:
                try:
                    self.output += os.read(self.master, 65536)
                except OSError:
                    pass
        actual = self.process.returncode
        assert actual == code, (actual, self.output)
        return actual

    def ready(self, start=0):
        return self.expect(b"\x1b[?2004hx2c> ", start)

    def attributes(self):
        return termios.tcgetattr(self.slave)

    def close(self):
        if self.process.poll() is None:
            os.killpg(self.process.pid, signal.SIGKILL)
            self.process.wait()
        os.close(self.master)
        os.close(self.slave)

    def __enter__(self):
        self.expect(b"x2c> ")
        return self

    def __exit__(self, *_):
        self.close()


objects = sorted(p for p in (ROOT / "builds/0/src").glob("*.o")
                 if p.name != "main.o")
subprocess.run([str(ROOT / "builds/0/x2c"), "build", "--plain",
                "--kind", "static-library", "--output", str(BUILD / "compiler.a"),
                *map(str, objects)], cwd=ROOT, check=True,
               capture_output=True, text=True)
api_binary = BUILD / "api-check"
subprocess.run([str(ROOT / "builds/0/x2c"), "build", "--plain",
                "--build-dir", str(BUILD / "api-native"),
                "--output", str(api_binary), "--x-include-dir", "src",
                "--c-include-dir", "builds/0/src",
                "tools/repl-spike/api-check.x",
                str(BUILD / "compiler.a")], cwd=ROOT, check=True,
               capture_output=True, text=True)
print(subprocess.check_output([str(api_binary)],
                              cwd=ROOT, text=True).strip())


check((ROOT / "tools/repl-spike/demo.txt").read_text(),
      "ok\nok\n=> 12\ndefined plus\n=> 15\ndefined twice\n=> 32\n"
      "=> 32\nok\n=> 48\n", "expected atomic expression")
check("int n = 10;\nint n = 99;\nn;\n"
      "int f(int x) { return n+x; }\nint f(int x) { return 99; }\nf(2);\n",
      "ok\n=> 10\ndefined f\n=> 12\n", "redeclaration is disabled")
check("int n = 10;\nint bad(int x) { goto end; end: return x; }\n"
      "int bad(int x) { return x+n; }\nbad(2);\n",
      "ok\ndefined bad\n=> 12\n", "a goto has no lowering")
check("int n = 10;\nint f(void) { n += 1; return 1/0; }\nf();\nn;\n",
      "ok\ndefined f\n=> 11\n", "evaluation failed: (div-zero")
check("int n = 0;\nint next(void) { n += 1; return n; }\n"
      "int x = next();\nx;\nn;\nx;\nn;\n",
      "ok\ndefined next\nok\n=> 1\n=> 1\n=> 1\n=> 1\n")
check("int y = 1/0;\ny;\nint y=7;\ny;\n", "ok\n=> 7\n",
      "unresolved identifier: y")
check("int n = 10;\nunknown;\nn;\n", "ok\n=> 10\n",
      "unresolved identifier: unknown")
check("int n = 10;\nint broken(\n:cancel\nn;\n", "ok\n=> 10\n")
check("int broken(int hidden) { return hidden + ; }\nhidden;\n",
      "", "unresolved identifier: hidden")
check("int broken(int hidden,\n:cancel\nhidden;\n",
      "", "unresolved identifier: hidden")
check("1 +\n2;\n", "=> 3\n")
check("1 + ;\n", "", "  1 + ;")
check("int n =", "", "incomplete input at EOF", 1)
check("int n =\n:quit\n", "")
result = run("1+2;\n", "--dump", "--stats")
assert result.returncode == 0 and result.stdout == "=> 3\n", result
assert all(part in result.stderr for part in
           ["typed:", "lowered:", "session: definitions=0",
            "evaluation (since REPL open): calls=",
            "scope (process): live-allocation-objects=",
            "pool (process): backing-capacity-bytes="]), result
result = run("", "--unknown")
assert result.returncode == 2 and "unknown option" in result.stderr, result
result = run("1 +\n:help\n2;\n")
assert result.returncode == 0 and result.stdout.endswith("=> 3\n"), result
assert all(text in result.stdout for text in [
    "\nCommands\n", "  :help             Show this help.\n",
    "\nEditing\n", "\nOptions\n",
]) and not result.stderr, result
check('String s = "hello";\ns.len();\ns;\n', 'ok\n=> 5\n=> "hello"\n')
check('"%s=%04d".format(%("answer" 42));\n',
      '=> "answer=0042"\n')
check('"%d".format(%("bad"));\n1+2;\n', '=> 3\n',
      'evaluation failed: (format (offset 0)')
check('int count = 3;\nprint("value=");\nprintln(%"$count");\n',
      'ok\nvalue=ok\n3\nok\n')
check('print("");\nprintln("");\n', 'ok\n\nok\n')
check('void nothing(void) {}\nnothing();\n', 'defined nothing\nok\n')
check('void print(String text) {}\nprintln("still usable");\n',
      'still usable\nok\n', 'function redeclaration is disabled')
check('List xs = %(1 2 3);\nxs.len();\nxs[1];\n'
      'Array a = [];\na.push(7);\na[0] = 9;\na[0];\n',
      'ok\n=> 3\n=> 2\nok\n=> 7\nok\n=> 9\n')
check('const int n = 4;\n', '', 'const and volatile need native checks')
check("unsigned char c = 258;\n(int)c;\n", "ok\n=> 2\n")
check("int fact(int n) { return n < 2 ? 1 : n * fact(n-1); }\nfact(6);\n",
      "defined fact\n=> 720\n")
check("int forever(void) { while (1) {} return 0; }\nforever();\n2+3;\n",
      "defined forever\n=> 5\n", '(why "steps")')

check(":symbols\n", "%()\n")
result = run("int tracked=1;\n:stats\n")
assert result.returncode == 0 and not result.stderr, result
assert result.stdout.startswith("ok\nsession: definitions=1\n"), result
for pattern in [
        r"evaluation \(since REPL open\): calls=\d+ machine-entries=\d+ "
        r"machine-errors=\d+",
        r"evaluation: live-program-bytes=\d+",
        r"scope \(process\): live-allocation-objects=\d+ "
        r"delta-since-open=[+-]\d+ live-requested-bytes=\d+ "
        r"byte-delta-since-open=[+-]\d+",
        r"scope \(process, since REPL open\): allocation-calls=\d+ "
        r"free-calls=\d+ reallocation-calls=\d+ "
        r"requested-traffic-bytes=\d+",
        r"pool \(current level, since REPL open\): "
        r"interned-identities=\d+ promotions=\d+",
        r"pool \(process\): backing-capacity-bytes=\d+ active-bytes=\d+ "
        r"active-blocks=\d+ depot-bytes=\d+ depot-blocks=\d+",
        r"pool \(process, since REPL open\): block-allocations=\d+ "
        r"block-reuses=\d+ slot-reuses=\d+",
]:
    assert re.search(pattern, result.stdout), (pattern, result)
result = run(":stats\nint after_stats=1;\n:stats\n")
assert result.returncode == 0 and not result.stderr, result
for field in ["allocation-calls", "free-calls", "reallocation-calls",
              "requested-traffic-bytes", "block-allocations",
              "block-reuses", "slot-reuses"]:
    values = [int(value) for value in
              re.findall(fr"\b{field}=(\d+)", result.stdout)]
    assert len(values) == 2 and values[1] >= values[0], (field, result)
result = run("int hot(int x) { return x+1; }\n"
             "hot(1);\nhot(2);\nhot(3);\n:stats verbose\n")
assert result.returncode == 0 and not result.stderr, result
for text in ["evaluation (verbose, since REPL open): analyses=",
             "scope (process, verbose): live-scopes=",
             "pool (verbose): depth=", "machine (since REPL open):",
             "prepared-calls=", "native-calls=", "lisp-returns="]:
    assert text in result.stdout, (text, result)
assert re.search(r"machine-entries=[1-9]\d*", result.stdout), result
result = run("int hot(int x) { return x+1; }\nhot(1);\nhot(2);\n",
             "--stats", "--verbose-stats")
assert result.returncode == 0, result
assert result.stderr.count("session: definitions=") == 1, result
assert "machine (since REPL open):" in result.stderr, result
result = run(":stats detailed\n")
assert result.returncode == 1 and result.stdout == "", result
assert result.stderr == "usage: :stats [verbose]\n", result
check("int z=1, a=2;\nint middle(void) { return a+z; }\n:symbols\n",
      'ok\ndefined middle\n%((value "a") (function "middle") (value "z"))\n')
check("int lost=1, failed=1/0;\n:symbols\n",
      "%()\n", "evaluation failed:")
check("int bad(void) { goto end; end: return 0; }\n:symbols\n",
      "%()\n", "a goto has no lowering")
check("int pending(\n:symbols\n:cancel\n:symbols\n", "%()\n%()\n")
result = run("int f(int x) { return x+1; }\n:ast f\n:lowered f\n"
             "int later=3;\nf(later);\n:ast f\n:lowered f\n")
assert result.returncode == 0 and not result.stderr, result
assert result.stdout.startswith("defined f\n"), result
before, after = result.stdout[len("defined f\n"):].split("ok\n=> 4\n")
assert before == after, result
typed, lowered = before.split("\nlowered: ")
assert typed.startswith("typed: %(function "), result
assert lowered.startswith("(") and typed[len("typed: %"):] != lowered, result
result = run("int n=2;\n1 +\n:ast\n:lowered f extra\n:stats extra\n:unknown\n"
             ":ast missing\n:lowered n\n:symbols extra\n:symbols\n2;\n")
assert result.returncode == 1, result
assert result.stdout == 'ok\n%((value "n"))\n=> 3\n', result
assert result.stderr.splitlines() == [
    "usage: :ast NAME", "usage: :lowered NAME",
    "usage: :stats [verbose]", "unknown command: :unknown",
    "not a session function: missing",
    "not a session function: n", "usage: :symbols"], result
result = run("int f(void) { return 3; }\n1 +\n  :ast\tf  \n"
             "\t:lowered \t f\t\n2;\n")
assert result.returncode == 0 and not result.stderr, result
assert result.stdout.startswith("defined f\ntyped: %(function "), result
assert "\nlowered: (" in result.stdout, result
assert result.stdout.endswith("=> 3\n"), result

check("unknown;\nint pending =\n:quit\n", "", "unresolved identifier")
check(":unknown\n:quit\n", "", "unknown command")

check("int counter(void) { static int n=0; n+=1; return n; }\n"
      "int missing(void) { extern int absent; return absent; }\n"
      "int thread(void) { threaded int n=0; return n; }\n:symbols\n"
      "int counter(void) { return 7; }\ncounter();\n",
      "%()\ndefined counter\n=> 7\n", "storage need native execution")
result = run("", "--help")
assert result.returncode == 0 and "x2c repl" in result.stdout, result
result = run("", "source.x")
assert result.returncode == 2 and "repl accepts no operands" in result.stderr, result

# Interactive editing and history run through a pseudo-terminal. Markers make
# each assertion independent of redisplay escape sequences already observed.
with PtyRepl() as repl:
    mark = repl.send(b":he\t\r")
    repl.expect(b"Commands", mark)
    repl.ready(mark)
    mark = repl.send(b"\t\t")
    repl.expect(b"Commands", mark)
    repl.expect(b"Keywords", mark)
    repl.expect(b"Types", mark)
    repl.send(b"\x03")
    repl.ready(mark)
    repl.send(b":quit\r")
    repl.wait()

with PtyRepl() as repl:
    mark = repl.send(b"int zebra(void) { return 9; }\r")
    repl.expect(b"defined zebra", mark)
    repl.ready(mark)
    mark = repl.send(b"int zed=1;\r")
    repl.expect(b"ok", mark)
    repl.ready(mark)
    mark = repl.send(b"\t\t")
    for heading in [b"Commands", b"Session", b"Types",
                    b"Functions and macros"]:
        repl.expect(heading, mark)
    repl.send(b"\x03")
    repl.ready(mark)
    mark = repl.send(b":ast z\t\r")
    repl.expect(b"typed: %(function", mark)
    repl.ready(mark)
    mark = repl.send(b"1 +\r")
    repl.expect(b"... ", mark)
    mark = repl.send(b":ca\t\r")
    repl.ready(mark)
    repl.send(b":quit\r")
    repl.wait()

with PtyRepl() as repl:
    mark = repl.send(b"143;\x1b[H\x1b[C\x1b[3~2\x1b[F\x1b[D\x1b[D\x1b[C\r")
    repl.expect(b"=> 123", mark)
    repl.ready(mark)
    mark = repl.send(b"\"\xc3\xa9\";\x1b[D\x1b[D\x7f\r")
    repl.expect(b'=> ""', mark)
    repl.ready(mark)
    mark = repl.send(b":quit\r")
    repl.wait()
    assert repl.attributes() == repl.original

with PtyRepl() as repl:
    mark = repl.send(b"41+1;\r")
    repl.expect(b"=> 42", mark)
    repl.ready(mark)
    mark = repl.send(b"\x1b[A\r")
    repl.expect(b"=> 42", mark)
    repl.ready(mark)
    mark = repl.send(b":symbols\r")
    repl.expect(b"%()", mark)
    repl.ready(mark)
    mark = repl.send(b"\x1b[A\r")
    repl.expect(b"%()", mark)
    repl.ready(mark)
    repl.send(b":quit\r")
    repl.wait()

with PtyRepl() as repl:
    mark = repl.send(b"Array kept=[];\r")
    repl.expect(b"ok", mark)
    repl.ready(mark)
    mark = repl.send(b"kept.pu\t(7);\r")
    repl.expect(b"=> 7", mark)
    repl.ready(mark)
    mark = repl.send(b"kept.\t\t")
    repl.expect(b"  push", mark)
    repl.send(b"\x03")
    repl.ready(mark)
    mark = repl.send(b'"x".for\t')
    repl.expect(b'"x".format', mark)
    repl.send(b"\x03")
    repl.ready(mark)
    mark = repl.send(b"int zebra(void) { return 9; }\r")
    repl.expect(b"defined zebra", mark)
    repl.ready(mark)
    mark = repl.send(b"zeb\t();\r")
    repl.expect(b"=> 9", mark)
    repl.ready(mark)
    repl.send(b":quit\r")
    repl.wait()

with PtyRepl() as repl:
    mark = repl.send(b"1 +\r")
    repl.expect(b"... ", mark)
    mark = repl.send(b"2;\r")
    repl.expect(b"=> 3", mark)
    repl.ready(mark)
    mark = repl.send(b"\x1b[A\r")
    repl.expect(b"=> 3", mark)
    repl.ready(mark)
    repl.send(b":quit\r")
    repl.wait()

with PtyRepl() as repl:
    mark = repl.send(b"1 + ;\r")
    repl.expect(b"1 + ;", mark)
    repl.ready(mark)
    mark = repl.send(b"\x1b[A\x1b[D\x1b[D2\r")
    repl.expect(b"=> 3", mark)
    repl.ready(mark)
    repl.send(b":quit\r")
    repl.wait()

with PtyRepl(columns=12) as repl:
    mark = repl.send(b"1234567890+1;\x1b[D\x7f2\r")
    repl.expect(b"=> 1234567892", mark)
    repl.ready(mark)
    assert b"\x1b[1A" in repl.output[mark:], repl.output[mark:]
    repl.send(b":quit\r")
    repl.wait()

with PtyRepl() as repl:
    mark = repl.send(b"\x1b[200~1 +\n2;\x1b[201~\r")
    repl.expect(b"=> 3", mark)
    assert b"\x1b[?2004l" in repl.output[mark:]
    repl.ready(mark)
    mark = repl.send(b"\x1b[A\r")
    repl.expect(b"=> 3", mark)
    repl.ready(mark)
    repl.send(b":quit\r")
    repl.wait()

with PtyRepl() as repl:
    mark = repl.send(b"int pending(\r")
    repl.expect(b"... ", mark)
    mark = repl.send(b"discard me\x03")
    repl.ready(mark)
    mark = repl.send(b":symbols\r")
    repl.expect(b"%()", mark)
    repl.ready(mark)
    repl.send(b":quit\r")
    repl.wait()

with PtyRepl() as repl:
    repl.send(b"\x04")
    repl.wait()
    assert repl.attributes() == repl.original

with PtyRepl() as repl:
    mark = repl.send(b"unknown;\r")
    repl.expect(b"unresolved identifier: unknown", mark)
    repl.ready(mark)
    repl.send(b"\x04")
    repl.wait()
    assert repl.attributes() == repl.original

with PtyRepl() as repl:
    mark = repl.send(b"\x1b[200~" + b"x" * (1024 * 1024 + 1) +
                     b"\x1b[201~")
    repl.expect(b"size-limit", mark, timeout=30)
    repl.wait(-signal.SIGABRT, timeout=30)
    assert repl.attributes() == repl.original

with PtyRepl() as repl:
    mark = repl.send(b"int pending =\r")
    repl.expect(b"... ", mark)
    repl.send(b"\x04")
    repl.wait(1)
    assert b"incomplete input at EOF" in repl.output
    assert repl.attributes() == repl.original

# Raw mode is active while editing, but evaluation runs in the original
# canonical mode. SIGINT during evaluation therefore keeps terminating x2c.
with PtyRepl() as repl:
    lflag = repl.attributes()[3]
    assert not lflag & termios.ICANON and not lflag & termios.ECHO
    mark = repl.send(b"int forever(void) { while (1) {} return 0; }\r")
    repl.expect(b"defined forever", mark)
    repl.ready(mark)
    mark = repl.send(b"forever();\r")
    repl.expect(b"\x1b[?2004l", mark)
    deadline = time.monotonic() + 5
    while True:
        lflag = repl.attributes()[3]
        if lflag & termios.ICANON and lflag & termios.ECHO:
            break
        assert time.monotonic() < deadline, lflag
        time.sleep(0.01)
    assert lflag & termios.ICANON and lflag & termios.ECHO
    os.killpg(repl.process.pid, signal.SIGINT)
    repl.wait(-signal.SIGINT, timeout=5)
    assert repl.attributes() == repl.original

with PtyRepl(term="dumb") as repl:
    assert b"\x1b[?2004h" not in repl.output
    repl.send(b":quit\n")
    repl.wait()

# The same authored functions execute through native compilation and lowering.
functions = """int total = 12;
int plus(int x) { return total + x; }
int twice(int x) { return plus(x) * 2; }
int sum(int n) { int s=0; for(int i=0;i<n;i++) s+=i; return s; }
"""
expressions = ["plus(3)", "twice(4)", "sum(1000)"]
result = run(functions + "\n".join(e + ";" for e in expressions) + "\n",
             "--stats")
interpreted = [line[3:] for line in result.stdout.splitlines()
               if line.startswith("=> ")]
assert result.returncode == 0 and len(interpreted) == 3, result
native_source = BUILD / "parity.x"
native_binary = BUILD / "parity"
native_source.write_text('#include <stdio.h>\n' + functions +
                         'int main(void) {\n' +
                         '\n'.join('printf("%d\\n", ' + e + ');'
                                   for e in expressions) + '\nreturn 0;\n}\n')
subprocess.run([str(ROOT / "builds/0/x2c"), "build", "--output",
                str(native_binary), str(native_source)], cwd=ROOT,
               check=True, capture_output=True, text=True)
native = subprocess.check_output([str(native_binary)], text=True).splitlines()
assert interpreted == native, (interpreted, native)
assert not re.search(r"machine-entries=0\b", result.stderr), result.stderr
print("REPL terminal checks and native parity passed:", ", ".join(native))
print(result.stderr.strip())

startup = []
for _ in range(7):
    start = time.perf_counter()
    assert run("").returncode == 0
    startup.append(time.perf_counter() - start)
source = "int n = 0;\n" + "n += 1;\n" * 1000 + "n;\n"
start = time.perf_counter()
result = run(source)
elapsed = time.perf_counter() - start
assert result.stdout.endswith("=> 1000\n") and not result.stderr, result
base = statistics.median(startup)
print(f"Warm process startup median: {base*1000:.1f} ms (7 runs)")
print(f"1002 submissions: {elapsed*1000:.1f} ms total; "
      f"{(elapsed-base)*1000/1002:.3f} ms/input after startup estimate")
