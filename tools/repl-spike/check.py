#!/usr/bin/env python3
"""Optional focused checks for the local REPL spike; not a repository gate."""
import pathlib
import statistics
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]
BINARY = ROOT / "unittest/build/repl-spike/repl"
SEED = ROOT / "unittest/build/repl-spike/seed.x"


def run(source, *args):
    return subprocess.run([str(BINARY), str(SEED), *args], input=source,
                          text=True, capture_output=True, cwd=ROOT, timeout=20)


def check(source, stdout, error="", code=0):
    result = run(source)
    assert result.returncode == code, result
    assert result.stdout == stdout, result
    assert error in result.stderr, result
    if not error:
        assert not result.stderr, result.stderr


api_binary = SEED.parent / "api-check"
subprocess.run([str(ROOT / "builds/0/x2c"), "build", "--plain",
                "--build-dir", str(SEED.parent / "api-native"),
                "--output", str(api_binary), "--x-include-dir", "src",
                "--c-include-dir", "builds/0/src",
                "tools/repl-spike/api-check.x", "tools/repl-spike/session.x",
                str(SEED.parent / "compiler.a")], cwd=ROOT, check=True,
               capture_output=True, text=True)
print(subprocess.check_output([str(api_binary), str(SEED)],
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
check("int n =", "", "incomplete input at EOF", 1)
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
native_source = SEED.parent / "parity.x"
native_binary = SEED.parent / "parity"
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
print("18 recovery/subset checks and native parity passed:", ", ".join(native))
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
