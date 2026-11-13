#!/usr/bin/env python3
"""Optional process benchmarks for the recursive and word-machine Lisps.

Run with --build once, then reuse the binaries for further measurements.
Every sample starts a fresh process and includes startup, standard-library
initialization, reading, compilation (word machine), evaluation, and output.
These are end-to-end timings, not isolated evaluator timings. The startup
case provides context; its time is not subtracted from other measurements.
"""

import argparse
from pathlib import Path
import platform
import statistics
import subprocess
import time


ROOT = Path(__file__).resolve().parents[2]
NUMBERS = "'(" + " ".join(map(str, range(1, 101))) + ")"
CASES = {
    "startup": ("42", 42),
    "fibonacci": ("""
(defun fib (n)
  (if (< n 2) n
    (+ (fib (- n 1)) (fib (- n 2)))))
(fib 20)
""", 6765),
    "lists": (f"""
(defun work (n)
  (if (= n 0) 0
    (+ (foldl + 0 (map (lambda (x) (* x x)) {NUMBERS}))
       (work (- n 1)))))
(work 20)
""", 6767000),
    "closures": (f"""
(defun make-adder (n) (lambda (x) (+ n x)))
(def add7 (make-adder 7))
(defun work (n)
  (if (= n 0) 0
    (+ (foldl + 0 (map add7 {NUMBERS}))
       (work (- n 1)))))
(work 20)
""", 115000),
    "macros": ("""
(defmacro twice (x) `(+ ,x ,x))
(defun work (n)
  (if (= n 0) 0
    (+ (twice n) (work (- n 1)))))
(work 200)
""", 40200),
}


def sample(command, source, expected):
    start = time.perf_counter()
    result = subprocess.run(command + ["-e", source], cwd=ROOT,
                            capture_output=True, timeout=30)
    elapsed = time.perf_counter() - start
    actual = result.returncode, result.stdout, result.stderr
    wanted = 0, f"{expected}\n".encode(), b""
    if actual != wanted:
        raise RuntimeError(
            f"{command[0]}: expected {wanted!r}, got {actual!r}")
    return elapsed * 1000


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", default="/tmp/reference-lisp")
    parser.add_argument("--word-machine", default="/tmp/x2c-lisp-oracle")
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--repeat", type=int, default=6,
                        help="samples per implementation (even; default 6)")
    parser.add_argument("--warmup", type=int, default=2,
                        help="untimed samples per implementation (default 2)")
    parser.add_argument("--case", choices=CASES, action="append",
                        help="run only this case; may be repeated")
    parser.add_argument("--show-source", action="store_true",
                        help="print selected Lisp programs without running")
    args = parser.parse_args()
    if args.repeat < 2 or args.repeat % 2 or args.warmup < 0:
        parser.error("use even --repeat >= 2 and --warmup >= 0")
    selected = args.case or CASES
    if args.show_source:
        for name in selected:
            source, expected = CASES[name]
            print(f"// {name}: expected {expected}\n{source.strip()}\n")
        return
    if args.build:
        for source, output in (("literate-lisp.x", args.reference),
                               ("lisp.x", args.word_machine)):
            subprocess.run([str(ROOT / "builds/0/x2c"), "build", "--output",
                            str(Path(output).resolve()),
                            str(ROOT / "examples/programs" / source)],
                           cwd=ROOT, check=True)
    commands = [
        [str(Path(args.reference).resolve())],
        [str(Path(args.word_machine).resolve()),
         "--init", str(ROOT / "etc/init.xlisp")],
    ]
    print(f"{platform.platform()}; "
          f"{args.repeat} samples, {args.warmup} warmups")
    print("Fresh processes; includes startup/init/read/compile/eval/output.")
    print("Median milliseconds; ratio = recursive / word machine.")
    print(f"{'case':<14} {'recursive':>12} {'word machine':>14} {'ratio':>9}")
    for name in selected:
        source, expected = CASES[name]
        times = [[], []]
        # Alternate which implementation runs first, equally often when timed.
        for iteration in range(-args.warmup, args.repeat):
            for index in ((0, 1) if iteration % 2 == 0 else (1, 0)):
                elapsed = sample(commands[index], source, expected)
                if iteration >= 0:
                    times[index].append(elapsed)
        recursive, machine = map(statistics.median, times)
        print(f"{name:<14} {recursive:12.3f} {machine:14.3f} "
              f"{recursive / machine:8.2f}x", flush=True)
    print("Every sample matched its expected result with no errors.")


if __name__ == "__main__":
    main()
