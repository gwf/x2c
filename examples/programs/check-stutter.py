#!/usr/bin/env python3
"""Optional differential check against the book's original stutter.c.

Pass compiled programs with --reference and --executable. With --book, also
run data/sample.slp, data/demo.slp, and data/float.slp from that checkout.
Compare stdout and exit status; collector schedules depend on representation.
Use --exact between x2c versions to compare diagnostics and collection too.
"""

import argparse
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def cases():
    yield "empty", ""
    yield "atoms", "nil t () '() '123 'a.b '\"text\" car if\n"
    yield "reader", "'abc; comment\n'(one\n two) ''a '(a . b)\n"
    yield "lists", (
        "(car nil) (cdr nil) (car '((a b) c)) (cdr '(a b)) "
        "(cons 'a nil) (cons '(a b) '(c d))\n"
    )
    yield "identity", (
        "(equal nil nil) (equal 'x 'x) (equal 'x 'y) "
        "(equal '(x) '(x)) (equal car car)\n"
    )
    yield "truth", (
        "(if nil absent 'no) (if '(nil) 'yes absent) "
        "(if '0 'yes absent) (if nil 'yes)\n"
    )
    yield "arity", (
        "(car '(a b) (set 'x 'effect) ignored) x "
        "((lambda (x y) (cons x (cons y nil))) 'a) "
        "((lambda (x) x) 'a absent) "
        "((lambda (x x) x) 'first 'second) "
        "(lambda (x) x ignored) (lambda nil) (equal nil) "
        "(set 'x) (quote a ignored)\n"
    )
    yield "dynamic-scope", (
        "(set 'x 'global) (set 'f (lambda () x)) "
        "((lambda (x) (f)) 'local) x "
        "((lambda (x) (set 'x 'changed)) 'local) x "
        "((lambda (x) (set 'new 'persistent)) 'local) new\n"
    )
    yield "argument-order", (
        "(set 'x 'old) "
        "((lambda (x y) (cons x (cons y nil))) (set 'x 'new) x) "
        "((lambda (x y) y) 'local x)\n"
    )
    yield "duplicate-parameter-mutation", (
        "(set 'x 'global) "
        "((lambda (x x) (set 'x 'changed)) 'first 'second) x "
        "((lambda (x) (cons "
        "((lambda (x x) (set 'x 'changed)) 'first 'second) "
        "(cons x nil))) 'outer) x\n"
    )
    yield "actual-effects-before-binding", (
        "(set 'x 'global) "
        "((lambda (x y) x) 'local (set 'x 'changed)) x "
        "((lambda (x) (cons "
        "((lambda (x y) x) 'inner (set 'x 'changed-outer)) "
        "(cons x nil))) 'outer) x\n"
    )
    yield "no-closure", (
        "(set 'x 'global) "
        "(set 'f ((lambda (x) (lambda () x)) 'lost)) (f)\n"
    )
    yield "rebind-builtins", (
        "(set 'q quote) (set 'quote (lambda (x) x)) "
        "(q untouched) 'nil\n"
    )
    yield "rebind-identities", (
        "(set 'saved-car car) (set 'car 'changed) "
        "(saved-car '(a b)) (set 'nil 'truthy) (if nil 'yes 'no) "
        "(saved-car '()) (equal 'nil 'nil) "
        "(set 't 'nil) t (if t 'yes 'no)\n"
    )
    yield "rebind-active-function", (
        "(set 'keep car) (car '(a b) (set 'car 'changed)) "
        "(keep '(x y))\n"
    )
    yield "recursion", (
        "(set 'append (lambda (x y) "
        "(if x (cons (car x) (append (cdr x) y)) y))) "
        "(append '(a b c) '(d e))\n"
    )
    yield "errors", (
        "absent (car 'a) (cdr 'a) (cons 'a 'b) "
        "(set '(a) 'b) (lambda ((a)) a) "
        "(if absent 'yes 'no) (equal absent absent) "
        "(car absent absent) (t 'foo)\n"
    )
    yield "argument-error-recovery", (
        "(set 'x 'global) "
        "((lambda (x y) y) 'local absent) x "
        "((lambda (x) x) absent) x\n"
    )
    yield "parse-recovery", ") ignored\n'ok\n(a\n"
    yield "scanner-chunks", (
        "'(" + "a" * 270 + ")\n;" + " " * 260 + "'after-comment\n"
    )
    yield "carriage-return", "'a\rb 'c\r\n"
    yield "nul-input", "'before\0'ignored\n'after\n"
    yield "dangling-quote", "'"
    yield "error-atom", "<error> '<error> '(a <error> b)\n'ok\n"


def exact_cases():
    yield "diagnostic-text", '50% $name "quoted" {braces} back\\slash\n'
    yield "zero-arguments", (
        "(car) (cdr) (cons) (set) (equal) (quote) (lambda) (if)\n"
    )
    yield "missing-operands", (
        "(cons 'a) (set 'x) x (if t) (if nil) "
        "((lambda (x y) (cons x (cons y nil))))\n"
    )
    yield "malformed-specials", (
        "(lambda 'x 'x) (lambda (car) car) (lambda (nil) nil) "
        "(lambda (<error>) 'ok) (if) (quote) '\n"
    )


def diagnostics(result, executable):
    # Only argv[0] in the two CLI diagnostics may differ between binaries.
    program = executable.encode()
    return (result.stderr
            .replace(b"Usage: " + program + b" [ options ]\n",
                     b"Usage: <program> [ options ]\n")
            .replace(program + b': unknown or incorrectly used option "',
                     b'<program>: unknown or incorrectly used option "'))


def run(executable, source, options=()):
    return subprocess.run([executable, *options], input=source,
                          capture_output=True, timeout=60)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--executable", default="/tmp/stutter")
    parser.add_argument("--book", type=Path)
    parser.add_argument("--exact", action="store_true",
                        help="compare x2c versions including stderr and "
                             "defined behavior absent from the C original")
    args = parser.parse_args()
    corpus = [(name, source.encode(), ()) for name, source in cases()]
    corpus.append(("showcase", (ROOT / "examples/data/stutter.slp")
                   .read_bytes(), ()))
    if args.book:
        for name in ("sample", "demo", "float"):
            source = (args.book / "data" / f"{name}.slp").read_bytes()
            corpus.append((f"book-{name}", source, ()))
    for options in (("-help",), ("--help",), ("-heap",), ("unknown",),
                    ("-heap", "128"), ("-heap", "128", "-heap", "256")):
        corpus.append(("cli-" + "-".join(options), b"", options))
    corpus.extend([
        ("gc", b"(cons t '(t t t t))\n" * 200, ("-heap", "128")),
        ("gc-calls", b"(set 'walk (lambda (xs) "
         b"(if xs (cons (car xs) (walk (cdr xs))) nil)))\n" +
         b"(walk '(t t t t))\n" * 200, ("-heap", "128")),
        ("exhaustion", b"'(" + b"t " * 300 + b")\n", ("-heap", "128")),
    ])
    corpus.append((
        "gc-shadowed-bindings",
        b"(set 'x '(t t t t t t t t)) "
        b"(set 'burn (lambda (xs) "
        b"(if xs (cons (car xs) (burn (cdr xs))) nil)))\n" +
        b"((lambda (x) (cons ((lambda (x) "
        b"(burn '(t t t t t t t t))) 'inner) (cons x nil))) "
        b"'(t t t t)) x\n" * 100,
        ("-heap", "256")))
    if args.exact:
        corpus.append((
            "gc-reassigned-argument",
            b"(set 'burn (lambda (xs) "
            b"(if xs (cons (car xs) (burn (cdr xs))) nil)))\n" +
            b"((lambda (x) (cons (set 'x nil) "
            b"(burn '(t t t t t t t t)))) "
            b"'(t t t t t t t t t t t t t t t t))\n" * 100,
            ("-heap", "128")))
        corpus.extend((name, source.encode(), ())
                      for name, source in exact_cases())
        for value in ("0", "-1", "", "abc", "1x", "2147483648",
                      "999999999999999999999999999999", "1", "19", "20",
                      "+128", " 128"):
            corpus.append((f"heap-{value!r}", b"", ("-heap", value)))
        corpus.append(("cli-updated-default", b"",
                       ("-heap", "128", "-help")))
    failures = 0
    for name, source, options in corpus:
        try:
            expected = run(args.reference, source, options)
            actual = run(args.executable, source, options)
        except subprocess.TimeoutExpired:
            failures += 1
            print(f"FAIL {name}: exceeded 60 seconds")
            continue
        agrees = ((actual.returncode, actual.stdout) ==
                  (expected.returncode, expected.stdout))
        if args.exact:
            agrees &= (diagnostics(actual, args.executable) ==
                       diagnostics(expected, args.reference))
        if name in ("gc", "gc-calls", "gc-shadowed-bindings"):
            agrees &= actual.returncode == 0
            agrees &= b"harvested " in actual.stderr
        if name == "exhaustion":
            agrees &= actual.returncode == 1
            agrees &= b"Garbage collection failed!" in actual.stderr
        if name.startswith("cli-") and expected.returncode:
            agrees &= b"-heap" in actual.stderr
        if not agrees:
            failures += 1
            print(f"FAIL {name}\n"
                  f"  reference: {expected.returncode}, "
                  f"{expected.stdout[:1000]!r}, {expected.stderr[:300]!r}\n"
                  f"  executable: {actual.returncode}, "
                  f"{actual.stdout[:1000]!r}, {actual.stderr[:300]!r}")
    print(f"{len(corpus) - failures}/{len(corpus)} cases agree")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
