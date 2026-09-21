#!/usr/bin/env python3
"""Optional focused checks for the integrated experimental REPL; not a repository gate."""
import os
import pathlib
import pty
import select
import signal
import tempfile
import statistics
import subprocess
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
           ["typed:", "lowered:", "Lisp calls="]), result
result = run("", "--unknown")
assert result.returncode == 2 and "unknown option" in result.stderr, result
result = run("1 +\n:help\n2;\n")
assert result.returncode == 0 and result.stdout.endswith("=> 3\n"), result
assert ":cancel" in result.stdout and not result.stderr, result
check('String s = "hello";\ns.len();\ns;\n', 'ok\n=> 5\n=> "hello"\n')
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
result = run("int n=2;\n1 +\n:ast\n:lowered f extra\n:unknown\n"
             ":ast missing\n:lowered n\n:symbols extra\n:symbols\n2;\n")
assert result.returncode == 1, result
assert result.stdout == 'ok\n%((value "n"))\n=> 3\n', result
assert result.stderr.splitlines() == [
    "usage: :ast NAME", "usage: :lowered NAME",
    "unknown command: :unknown", "not a session function: missing",
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

# A pseudo-terminal exercises interactive status and a real prompt before SIGINT.
for source in (b"unknown;\n:quit\n", None, b"int forever(void) { while (1) {} return 0; }\nforever();\n"):
    master, slave = pty.openpty()
    with subprocess.Popen([str(BINARY), "repl"], stdin=slave, stdout=slave,
                          stderr=slave, cwd=tempfile.gettempdir()) as process:
        os.close(slave)
        try:
            output = b""
            deadline = time.monotonic() + 20
            while b"x2c> " not in output:
                assert time.monotonic() < deadline, output
                ready, _, _ = select.select([master], [], [], 1)
                if ready:
                    output += os.read(master, 4096)
            if source:
                os.write(master, source)
            if source and b":quit" in source:
                assert process.wait(timeout=20) == 0
            else:
                if source:
                    while b"defined forever" not in output:
                        assert time.monotonic() < deadline, output
                        ready, _, _ = select.select([master], [], [], 1)
                        if ready:
                            output += os.read(master, 4096)
                    time.sleep(0.02)
                process.send_signal(signal.SIGINT)
                assert process.wait(timeout=5) == -signal.SIGINT
        finally:
            os.close(master)
            if process.poll() is None:
                process.kill()
                process.wait()

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
assert "machine entries=0 " not in result.stderr, result.stderr
print("39 terminal checks and native parity passed:", ", ".join(native))
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
