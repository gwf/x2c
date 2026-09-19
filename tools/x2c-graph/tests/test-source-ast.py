#!/usr/bin/env python3
"""Optional source-syntax inspection probe; not a publication gate."""

from pathlib import Path
import re
import subprocess
import sys
import tempfile


def run(compiler, source, mode, directory):
    return subprocess.run(
        [str(compiler), "translate", "--plain", mode, str(source)],
        cwd=directory, capture_output=True, text=True,
    )


def compact(text):
    return re.sub(r"\s+", " ", text).strip()


def main():
    tests = Path(__file__).resolve().parent
    root = tests.parents[2]
    compiler = (Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else
                root / "builds" / "0" / "x2c")
    source = tests / "fixtures" / "source-ast.x"
    with tempfile.TemporaryDirectory(prefix="x2c-source-ast-") as temp:
        directory = Path(temp)
        raw = run(compiler, source, "--dump-source-ast", directory)
        bound = run(compiler, source, "--dump-ast", directory)
        assert raw.returncode == 0, raw.stderr
        assert bound.returncode == 0, bound.stderr
        raw_text, bound_text = compact(raw.stdout), compact(bound.stdout)

        assert "(macro-invoke source_twice " in raw_text
        assert "(macro-invoke " not in bound_text
        assert '(macrodef (name source_twice) (kind expression)' in raw_text
        assert '(parameters ((macro-param (binder ?value) (kind expr)' in raw_text
        assert '(template (expr (macro-expr) (op +' in raw_text
        assert '(bind (("String") "source_probe") ' in raw_text
        assert '(op . (expr () (ident ("text"))) ("source_probe"))' in raw_text
        assert '"String_source_probe"' not in raw_text
        assert '"String_source_probe"' in bound_text

        assert '(cache ' not in raw_text, "source syntax hid literal contents"
        assert '(literal ("Symbol") "source" source)' in raw_text
        assert '(cons (expr () (ident ("value"))) (nil))' in raw_text
        assert '"int_var"' not in raw_text
        assert '"int_var"' in bound_text

        shadow = raw_text.split('(bind ("source_ast_shadow")', 1)[1]
        assert '(param (int) (bind ("value") ()))' in shadow
        assert '(op = (bind ("value") ())' in shadow
        assert '(postfix ++ (expr () (ident ("value"))))' in shadow
        assert '(return (expr () (ident ("value"))))' in shadow
        assert '(binding ' not in shadow
        assert '(source-lisp "(def source_ast_probe 1)")' in raw_text
        assert '(source-lisp ' not in bound_text
        assert '(bind (("SourceValue") "int") ' in raw_text
        assert '(op . (expr () (ident ("value"))) ("int"))' in raw_text
        assert '"SourceValue_int"' in bound_text
        assert '(delegate (declare ("SourceValue")' in raw_text
        assert '(delegate ' not in bound_text
        for operator in ('*', '&', 'in'):
            assert f'(op {operator} (expr () (ident ("local")))' in raw_text
        match = raw_text.split('(bind ("source_ast_match")', 1)[1]
        assert '(source-case case ' in match
        for symbol in ('!or', 'left', 'right'):
            assert f'(literal ("Symbol") "{symbol}" {symbol})' in match
        assert match.count('(typed-capture (int) ?value)') == 2
        assert '(return (expr () (ident ("value"))))' in match
        assert '(source-case default ' in match
        assert '(declare ' not in match, "match capture was lowered"
        assert '(source-case ' not in bound_text

        fixtures = root / "unittest" / "compiler-fixtures"
        corpus = {}
        for name in ("macro-construction-regressions", "macro-source-parity",
                     "lambda-nested-explicit-captures"):
            result = run(compiler, fixtures / f"{name}.x",
                         "--dump-source-ast", directory)
            assert result.returncode == 0, f"{name}: {result.stderr}"
            corpus[name] = compact(result.stdout)
        construction = corpus["macro-construction-regressions"]
        assert '(declare ("MyInt") (bindings (op = (bind ("is") ())' in construction
        parity = corpus["macro-source-parity"]
        assert '(macro-invoke generated_read ' in parity
        assert '(macro-invoke generated_macro_definition ' in parity
        assert '(bind ("generated_function")' not in parity
        captures = corpus["lambda-nested-explicit-captures"]
        assert captures.count('(source-capture & ("value"))') == 3
        assert '(binding ' not in captures
        assert not list(directory.iterdir()), "inspection emitted files"

        malformed = directory / "malformed.x"
        malformed.write_text("int broken(void) { return (1 + ; }\n")
        failed = run(compiler, malformed, "--dump-source-ast", directory)
        assert failed.returncode != 0, "malformed source was accepted"
        assert failed.stderr.strip(), "malformed source lacked a diagnostic"
        assert not failed.stdout.strip(), "malformed source emitted a tree"
        assert list(directory.iterdir()) == [malformed], "failure emitted files"
    print("source AST inspection probe passed")


if __name__ == "__main__":
    main()
