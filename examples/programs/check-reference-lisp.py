#!/usr/bin/env python3
"""Optional differential check of the recursive showcase against x2c Lisp.

Build both executables first, or pass --build. Each case gets fresh sessions;
exit status, stdout and stderr must agree byte for byte. Callable addresses
are deliberately absent from the corpus, so no output normalization is used.
"""

import argparse
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]


def cases():
    yield "callable-repr-kind", "(substring (repr (lambda () 1)) 0 8)"
    yield "callable-mixed-sort", (
        '(def sort (bind "List_sort" nil)) '
        '(map type (sort (list (lambda () 1) + 1 nil true "x")))'
    )
    yield "callable-binary-error", "(_binary 0 '+ (lambda () 1))"
    yield "empty", "// no forms\n"
    yield "values", '(list nil false true 0 "" 42 -42 2.5 2147483648)'
    yield 'names', (
        '(let ((CaseSensitiveLongName 7) (casesensitivelongname 9)) (+ '
        'CaseSensitiveLongName casesensitivelongname))'
    )
    yield 'types', (
        '(map type (list nil true 1 2147483648 1.5 "a" + (lambda () '
        '1)))'
    )
    yield 'predicates', (
        '(map (lambda (x) (list (atom? x) (pair? x) (list? x) (number? '
        'x) (symbol? x) (string? x) (procedure? x))) (list nil true 1 '
        '"a" \'(a) + quote (lambda () 1) (macro () 1)))'
    )
    yield 'truth', (
        '(list (if 0 1 2) (if "" 1 2) (if nil 1 2) (and) (or) (and 1 2)'
        ' (or nil 3))'
    )
    yield 'lists', (
        "(list (car nil) (cdr nil) (cons 1 nil) (reverse '(1 2 3)) "
        "(append '(1 2) nil '(3)) (length '(a b)))"
    )
    yield 'higher-order', (
        "(list (map (lambda (x) (* x x)) '(1 2 3)) (filter (lambda (x) "
        "(> x 2)) '(1 2 3 4)) (foldl + 0 '(1 2 3 4)))"
    )
    yield 'rest', (
        '(list ((lambda (. xs) xs)) ((lambda (x . xs) xs) 1 2 3) '
        '((lambda (x x) x) 1 2))'
    )
    yield 'capture', (
        '(def mk (lambda (n) (lambda (x) (+ x n)))) (list ((mk 5) 3) '
        '((mk 9) 3))'
    )
    yield 'scalar-capture', (
        '(def n 100) (def f ((lambda (n) (lambda () n)) 5)) (list (f) '
        '((lambda (n) (f)) 7))'
    )
    yield 'dynamic-caller', (
        '(def f (lambda () (+ absent 1))) ((lambda (absent) (f)) 41)'
    )
    yield 'global-rebind', (
        '(def x 1) (def f (lambda () (+ x 1))) (def x 9) (f)'
    )
    yield 'capture-quote', (
        "(def f ((lambda (x) (lambda () (eval 'x))) 8)) (def x 3) (f)"
    )
    yield 'special-alias', (
        '(def q quote) (def quote (lambda (x) (+ x 1))) (list (q hello)'
        ' (quote 4))'
    )
    yield "special-local", "((lambda (cond) (cond 4)) (lambda (x) (+ x 1)))"
    yield "eval-global", "(def x 10) ((lambda (x) (eval 'x)) 5)"
    yield "order", "(def x 0) (list (def x (+ x 1)) (def x (+ x 1)) x)"
    yield 'macro-once', (
        '(def x 0) (defmacro once (e) `(list ,e)) (list (once (def x (+'
        ' x 1))) x)'
    )
    yield "macro-caller", "(defmacro read-x () 'x) ((lambda (x) (read-x)) 42)"
    yield 'macro-recursion', (
        '(defmacro twice (e) `(+ ,e ,e)) (twice (twice 3))'
    )
    yield 'quasiquote', (
        "(list `(1 ,(+ 1 1) ,@'(3 4)) ``(a ,(b ,(+ 1 2))) `,(+ 1 2))"
    )
    yield 'apply', (
        "(list (apply + '(10 20 12)) (apply (lambda (. x) x) '(a b)) "
        "(apply apply (list + '(1 2 3))))"
    )
    yield 'native-identity', (
        '(eq? (bind "Var_car" \'()) (bind "Var_car" \'((func (("Var"))) '
        '"Var")))'
    )
    yield 'strings', (
        '(list (+ "a" 1 "b") (+ 1 "a") (string-append "a" "b") '
        '(substring "abcd" 1 3) (lower "AbC") (repr \'(a "b")))'
    )
    yield 'matching', (
        "(list (match '(a 2) '(a ?x)) (match-replace '(a 2) '(a ?x) "
        "'?x) (search-replace '(a (a 2)) '(a ?x) '?x) (match-case '(a "
        '2) ((a ?x) (+ ?x 1)) (else 0)))'
    )
    yield 'let', (
        '(def a 9) (list (let ((a 1) (b a)) b) (let* ((a 1) (b a)) b))'
    )
    yield 'recursion', (
        '(defun fact (n) (if (= n 0) 1 (* n (fact (- n 1))))) (map fact'
        " '(0 1 2 3 4 5 6))"
    )
    for op in ("+", "-", "*", "/", "=", "<", "<=", ">", ">="):
        for args in ("", "2", "2 3", "2 3 4", "2 2 2", '2 "x"'):
            yield f"numeric-{op}-{args}", f"({op} {args})"
    # Native signatures are visible in errors, including their return types.
    for name, source in (
        ("str", "(str)"),
        ("repr", "(repr 1 2)"),
        ("downcase", "(string-downcase 1)"),
        ("string-append", '(_string-append "a" 1)'),
    ):
        yield f"native-signature-{name}", source
    fixed_natives = (
        "Var_car", "Var_cdr", "Var_cons", "lisp_atom", "lisp_pair",
        "lisp_list", "lisp_eq", "lisp_type", "lisp_number", "lisp_string",
        "lisp_symbol", "lisp_procedure", "List_reverse", "List_len",
        "List_match", "lisp_match_replace", "List_search",
        "List_search_replace", "lisp_add", "Var_binary", "lisp_compare",
        "lisp_str", "lisp_repr", "String_len", "lisp_string_append",
        "lisp_substring", "lisp_string_downcase", "lisp_read_file",
        "lisp_write_file", "List_sort",
    )
    for native in fixed_natives:
        yield f"native-arity-{native}", f'((bind "{native}" nil))'
    for name, arguments in (
        ("reverse", "1"), ("length", "1"), ("_match", "1 nil"),
        ("match-replace", "1 nil nil"), ("search", "1 nil"),
        ("_search-replace", "1 nil nil"), ("string-length", "1"),
        ("substring", '"abc" "x" 1'),
    ):
        yield f"native-types-{name}", f"({name} {arguments})"
    errors = [
        "missing", "(1 2)", "(quote)", "(quote a b)", "(def)",
        "(def 1 2)", "(cond)", "(cond 1)", "(cond (true))",
        "(lambda x x)", "(lambda (x))", "((lambda (x) x))",
        "((lambda () 1) 2)", "((lambda (a .) a) 1)", "(eval)",
        "(apply + 7)", "(apply quote '(x))", "(apply (macro () 1) nil)",
        "(apply apply '(1))", "(apply apply '(+ 1))", "(quasiquote)",
        "`,@'(1)", "`(a ,@1)", "`(unquote 1 2)", "(import 1)",
        '(bind 1 nil)', '(bind "Var_car" 1)', '(bind "unknown" nil)',
        "(car 1)", "(cons 1 2)", '(substring 1 0 1)',
        "(", ")", "'", '"unterminated', '"\\z"',
        "(def x 1) )", "(def x 1) (", "(unquote 1)",
    ]
    for index, source in enumerate(errors):
        yield f"error-{index}", source


def run(command, source, repl=False):
    result = subprocess.run(command if repl else command + ["-e", source],
                            input=source.encode() if repl else None,
                            capture_output=True, timeout=15)
    return result.returncode, result.stdout, result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", default="/tmp/reference-lisp")
    parser.add_argument("--oracle", default="/tmp/x2c-lisp-oracle")
    parser.add_argument("--build", action="store_true")
    args = parser.parse_args()
    if args.build:
        for source, output in (("literate-lisp.x", args.reference),
                               ("lisp.x", args.oracle)):
            subprocess.run([str(ROOT / "builds/0/x2c"), "build", "--output",
                            output, str(ROOT / "examples/programs" / source)],
                           cwd=ROOT, check=True)
    oracle = [args.oracle, "--init", str(ROOT / "etc/init.xlisp")]
    reference = [args.reference]
    failures = []
    corpus = list(cases())
    showcase = ROOT / "examples/data/reference-lisp/showcase.xlisp"
    corpus.append(("showcase", showcase.read_text()))
    extras = ROOT / "etc/lisp-extras.xlisp"
    corpus.append(("extras", f'(import "{extras}") '
                   "(list (range 2 6) (sort '(3 1 2)) (fib 8) "
                   "(subst 'x 'a '(a (b a))))"))
    with tempfile.TemporaryDirectory(prefix="reference-lisp-check-") as temp:
        imported = Path(temp) / "module.xlisp"
        imported.write_text("(def imported 40) (+ imported 2)\n")
        corpus.append(("import", f'(list (import "{imported}") imported)'))
        corpus.append(("missing-import", f'(import "{temp}/missing")'))
        nul_file = Path(temp) / "nul.xlisp"
        nul_file.write_bytes(b"(def x 1)\0(+ x 1)")
        corpus.append(("nul-import", f'(import "{nul_file}")'))
        io = ROOT / "etc/lisp-io.xlisp"
        data = Path(temp) / "data.txt"
        corpus.append(("io", f'(import "{io}") '
                       f'(list (write-file "{data}" "hello") '
                       f'(read-file "{data}"))'))
        for name, source in corpus:
            try:
                expected = run(oracle, source)
                actual = run(reference, source)
            except subprocess.TimeoutExpired:
                failures.append(name)
                print(f"FAIL {name}: execution exceeded 15 seconds")
                continue
            if actual != expected:
                failures.append(name)
                print(f"FAIL {name}: {source}\n"
                      f"  oracle: {expected!r}\n  reference: {actual!r}")
    repl_cases = [
        ("repl-multiline", "(+ 1\n 2)\n"),
        ("repl-recovery", "(def x 1) missing (def x 2)\nx\n"),
        ("repl-reader-recovery", "(def x 1) )\nx\n"),
        ("repl-incomplete", "(+ 1\n"),
    ]
    for name, source in repl_cases:
        expected = run(oracle, source, repl=True)
        actual = run(reference, source, repl=True)
        if actual != expected:
            failures.append(name)
            print(f"FAIL {name}: {source!r}\n"
                  f"  oracle: {expected!r}\n  reference: {actual!r}")
    corpus.extend(repl_cases)
    print(f"{len(corpus) - len(failures)}/{len(corpus)} cases agree")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
