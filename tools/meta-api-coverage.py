#!/usr/bin/env python3
"""Report the standard meta-call surface without adding a build gate.

Run after building the current tree. By default, print a Markdown inventory;
--json prints the same evidence as JSON. --probe runs bounded inert examples.
--write refreshes docs/src/guide/meta-api-coverage.md. No mode edits bindings.
"""

from __future__ import annotations

import argparse
import hashlib
from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from x2c_source import definitions_for_path, function_spans, mask_non_code, split_signature
from x2c_symbols import (content_hash, load, _strip_param_name,
                         _unqualified, normalize_type)


ROOT = Path(__file__).resolve().parents[1]
REPORT = ROOT / "docs/src/guide/meta-api-coverage.md"
TYPES = ("String", "List", "Array", "Map", "Symbol", "Var")
STATES = ("verified example", "reproduced failure", "bound, unverified",
          "no binding found")

# These are adapter considerations, not explanations of historical intent.
CONSIDERATIONS = {
    "binding": "A binding/adapter candidate over represented values; inspect "
               "its contract before assuming a direct alias is sufficient.",
    "callback": "An interpreted callback needs a compatible call adapter, "
                "including order, empty input, and missing-value behavior.",
    "pointer": "Native pointer, output-parameter, or varargs arguments need "
               "representation-aware adaptation; evaluator cells are not C "
               "addresses.",
    "ownership": "Allocation ownership or lifetime transfer needs deliberate "
                 "compile-time semantics; evaluator objects cannot simply "
                 "be freed by their callers.",
    "resource": "Another resource or value type needs a supported "
                "representation and lifetime before this signature is useful.",
    "syntax": "Related language syntax has lowering, but this does not "
              "establish availability of the explicitly named method.",
    "internal": "Low-level representation or runtime-internal behavior "
                "needs investigation; feasibility is not established.",
}
OWNERSHIP = {
    "String": {"free", "intern_free", "malloc", "new_in", "promote",
               "try_own", "is_permanent"},
    "List": {"cons_in", "promote", "try_own"},
    "Array": {"cleanup", "free", "list_free"},
    "Map": {"cleanup", "export_to"},
    "Var": {"move_wide_to", "wide_owner", "register_object_tag"},
}
SYNTAX = {
    "String": {"truth"}, "List": {"truth"},
    "Array": {"truth", "updateindex", "postfixindex"},
    "Map": {"truth", "updateindex", "postfixindex"},
    "Var": {"truth", "binary", "add", "sub", "mul", "div", "mod",
            "neg", "matmul", "update", "postfix", "updateindex",
            "postfixindex"},
}
RESOURCES = re.compile(
    r"\b(?:Buffer|File|Split|Iter|Job|Pool|Scope|Context|Block|Bytes|AdNode|"
    r"JsonBool|Regex\w*|Token|Array(?:Char|Dbl|Float|Int|Long|Short|String)|"
    r"List(?:Char|Dbl|Float|Int|Short|String|Symbol)|"
    r"Map(?:IntInt|LongDouble|StringInt|StringString))\b"
)

# Each body returns a small integer checked through explicit evaluation.
# No file, process, arbitrary pointer, or ownership-transfer calls belong here.
PROBES = {
    'String.contains_digit': ('positive, negative and empty bytes',
        'String empty = ""; return "a1".contains_digit() && !"abc".contains_digit() && !empty.contains_digit();', 1),
    'String.is_alpha': ('positive, negative and empty bytes',
        'String empty = ""; return "Ab".is_alpha() && !"a1".is_alpha() && !empty.is_alpha();', 1),
    'String.is_alpha_under': ('positive, negative and empty bytes',
        'String empty = ""; return "a_B".is_alpha_under() && !"a1".is_alpha_under() && !empty.is_alpha_under();', 1),
    'String.is_digit': ('positive, negative and empty bytes',
        'String empty = ""; return "123".is_digit() && !"12a".is_digit() && !empty.is_digit();', 1),
    'String.is_alnum': ('positive, negative and empty bytes',
        'String empty = ""; return "a1B".is_alnum() && !"a_".is_alnum() && !empty.is_alnum();', 1),
    'String.is_alnum_under': ('positive, negative and empty bytes',
        'String empty = ""; return "a_1".is_alnum_under() && !"a-".is_alnum_under() && !empty.is_alnum_under();', 1),
    'String.is_identifier': ('positive, negative and empty bytes',
        'String empty = ""; return "_a1".is_identifier() && !"1a".is_identifier() && !empty.is_identifier();', 1),
    'String.is_space': ('positive, negative and empty bytes',
        'String empty = ""; return " \\t".is_space() && !" a".is_space() && !empty.is_space();', 1),
    'String.is_lower': ('positive, negative and empty bytes',
        'String empty = ""; return "abc".is_lower() && !"Ab".is_lower() && !empty.is_lower();', 1),
    'String.is_lower_under': ('positive, negative and empty bytes',
        'String empty = ""; return "a_b".is_lower_under() && !"a_B".is_lower_under() && !empty.is_lower_under();', 1),
    'String.is_upper': ('positive, negative and empty bytes',
        'String empty = ""; return "ABC".is_upper() && !"aB".is_upper() && !empty.is_upper();', 1),
    'String.is_upper_under': ('positive, negative and empty bytes',
        'String empty = ""; return "A_B".is_upper_under() && !"a_B".is_upper_under() && !empty.is_upper_under();', 1),
    'String.compare': ('native text contract and boundaries',
        'return "abc".compare("abd") < 0 && "abc".compare("abc") == 0;', 1),
    'String.hash#constant-receiver': ('native text contract and boundaries',
        'return "abc".hash() == ("a" + "bc").hash();', 1),
    'String.symbol': ('native text contract and boundaries',
        'return "alpha".symbol() == <alpha>;', 1),
    'String.dedent': ('native text contract and boundaries',
        'return "\\n  a\\n    b\\n  ".dedent().equal("a\\n  b\\n");', 1),
    'String.keep': ('native text contract and boundaries',
        'return "abacad".keep("ac").equal("aaca") && "x".keep("").len() == 0;', 1),
    'String.reject': ('native text contract and boundaries',
        'return "abacad".reject("ac").equal("bd") && "x".reject("").equal("x");', 1),
    'String.squeeze': ('native text contract and boundaries',
        'return "aaabbbccc".squeeze("ac").equal("abbbc") && "aa".squeeze("").equal("aa");', 1),
    'String.pad_left': ('native text contract and boundaries',
        'return "x".pad_left(3, \'.\').equal("..x") && "abc".pad_left(1, \'.\').equal("abc");', 1),
    'String.pad_right': ('native text contract and boundaries',
        'return "x".pad_right(3, \'.\').equal("x..");', 1),
    'String.pad_center': ('native text contract and boundaries',
        'return "x".pad_center(4, \'.\').equal(".x..");', 1),
    'String.new_fill': ('native text contract and boundaries',
        'return String.new_fill(\'x\', 3).equal("xxx") && String.new_fill(\'x\', -1).len() == 0;', 1),
    'String.find_within': ('native text contract and boundaries',
        'return "abcabc".find_within("c", -4, -1) == 2 && "abc".find_within("x", 0, -1) == -1;', 1),
    'String.replace_n': ('native text contract and boundaries',
        'return "aaaa".replace_n("a", "b", 2).equal("bbaa") && "aa".replace_n("a", "b", 0).equal("aa");', 1),
    'String.split_n': ('native text contract and boundaries',
        'return "a:b:c".split_n(":", 1).equal(%("a" "b:c")) && "a:b".split_n(":", 0).equal(%("a:b"));', 1),
    'String.lstrip#NULL': ('native text contract and boundaries',
        'return "  a  ".lstrip(NULL).equal("a  ") && "xxax".lstrip("x").equal("ax") && " ".lstrip(NULL).len() == 0;', 1),
    'String.rstrip#NULL': ('native text contract and boundaries',
        'return "  a  ".rstrip(NULL).equal("  a") && "xaxx".rstrip("x").equal("xa") && " ".rstrip(NULL).len() == 0;', 1),
    "String.hash": ("nonzero canonical String hash",
        'return "abc".hash() != 0;', 1),
    "String.lstrip": ("explicit charset and typed null pointer",
        'return " a ".lstrip(" ").equal("a ") && '
        '" a ".lstrip((char *) 0).equal("a ");', 1),
    "String.rstrip": ("explicit charset and typed null pointer",
        'return " a ".rstrip(" ").equal(" a") && '
        '" a ".rstrip((char *) 0).equal(" a");', 1),
    "String.len": ("nonempty text", 'return "abc".len();', 3),
    "String.strip#null": ("default whitespace through NULL", 'return " a ".strip(NULL).len();', 1),
    "String.strip#charset": ("explicit character set", 'return " a ".strip(" ").len();', 1),
    "List.car": ("first element", 'List xs = %(7 8); return xs.car();', 7),
    "List.cdr": ("tail", 'List xs = %(7 8); return xs.cdr().len();', 1),
    "List.caar": ("nested head", 'List xs = %((7) 8); return xs.caar();', 7),
    "List.cadr": ("second element", 'List xs = %(7 8); return xs.cadr();', 8),
    "List.cadr#absent": ("absent element distinguishes void from nil",
        'List xs = %(7); Var value = xs.cadr(); return value.kind() == <void>;', 1),
    "List.cddr": ("empty second tail", 'List xs = %(7 8); return xs.cddr().len();', 0),
    "List.caddr": ("third element", 'List xs = %(7 8 9); return xs.caddr();', 9),
    "List.cons": ("prepend", 'return List.cons(7, %(8)).len();', 2),
    "List.foldl": (
        "ordered fold with explicit seed",
        'List xs = %(1 2); Func f = %!(a, b) => a * 10 + b; '
        'return xs.foldl(3, f);', 312),
    "Array.push": (
        "append and read", 'Array xs = []; xs.push(7); return xs[0];', 7),
    "Array.map": (
        "interpreted callback", 'Array xs = [1, 2]; '
        'Array ys = xs.map(%!(x) => x + 1); return ys[1];', 3),
    "Array.truth": (
        "explicit empty-array method", 'Array xs = []; return xs.truth();', 0),
    "Map.setindex": (
        "store and read", 'Map m = {}; m.setindex("x", 7); return m["x"];', 7),
    "Map.keys": (
        "one key through iterator", 'Map m = {"x": 7}; '
        'struct Iter storage; List keys = m.keys(&storage).list(); '
        'return keys.len();', 1),
    "Symbol.len": ("short symbol", 'return <abc>.len();', 3),
    "Symbol.compare": ("lexical comparison", 'return <abc>.compare(<abd>) < 0;', 1),
    "Symbol.repr": ("symbol rendering", 'return <abc>.repr().equal("<abc>");', 1),
    "Var.kind": ("integer kind", 'Var value = 7; return value.kind() == <integer>;', 1),
    "Var.cadr": ("boxed List selector", 'Var value = %(7 8); return value.cadr();', 8),
    "Var.cons": ("prepend", 'return Var.cons(7, %(8)).len();', 2),
    "Var.array": (
        "explicit Array conversion", 'Var xs = [7]; return xs.array().len();', 1),
    "Var.binary": ("integer addition", 'return Var.binary(2, <+>, 3);', 5),
}


def library_files() -> list[str]:
    """Use the compiler's loader table, not a second list of Lisp layers."""
    text = (ROOT / "src/macros.x").read_text()
    for span in function_spans(mask_non_code(text), include_static=True):
        if span.name == "_library_files":
            return re.findall(r'"([^"\n]+\.xlisp)"',
                              text[span.body_start:span.end])
    raise ValueError("cannot find the compiler's _library_files loader")


def lisp_definitions(text: str):
    """Read names in top-level def/defun/defmacro forms, skipping bodies."""
    tokens = re.finditer(r'//[^\n]*|"(?:\\.|[^"\\])*"|[()]|[^\s()]+', text)
    depth, head, start = 0, [], 0
    for token in tokens:
        value = token.group()
        if value.startswith("//"):
            continue
        if value == "(":
            if depth == 0:
                head, start = [], token.start()
            depth += 1
        elif value == ")":
            depth -= 1
        elif depth == 1 and len(head) < 2:
            head.append(value)
            if len(head) == 2 and head[0] in ("def", "defun", "defmacro"):
                yield head[1], text.count("\n", 0, start) + 1


def session_bindings(files: list[str]) -> dict[str, list[str]]:
    bindings: dict[str, list[str]] = {}
    for name in files:
        for binding, line in lisp_definitions((ROOT / name).read_text()):
            bindings.setdefault(binding, []).append(f"{name}:{line}")
    # Native installation is separate from the loader's Lisp files.
    text = (ROOT / "src/macros.x").read_text()
    for match in re.finditer(r'\$lisp\.bind\([^,]+,\s*"([^"\n]+)"', text):
        line = text.count("\n", 0, match.start()) + 1
        bindings.setdefault(match[1], []).append(f"src/macros.x:{line}")
    return bindings


def ledger(path: str) -> dict:
    rows = {}
    for line in (ROOT / path).read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        source, kind, tail = line.split("|", 2)
        if path.endswith("tiers.txt"):
            for name in tail.split(","):
                rows[source, name] = kind
        else:
            rows[source] = kind
    return rows


def classify(row: dict) -> list[str]:
    owner, method = row["name"].split(".", 1)
    signature = row["signature"]
    flags = []
    if method in OWNERSHIP.get(owner, ()):
        flags.append("ownership")
    if RESOURCES.search(signature):
        flags.append("resource")
    if "*" in signature or "..." in signature:
        flags.append("pointer")
    if "Func " in signature:
        flags.append("callback")
    if method in SYNTAX.get(owner, ()):
        flags.append("syntax")
    if row["tier"] == "internal" or row["visibility"] == "internal":
        flags.append("internal")
    elif owner == "Var" and any(part in method for part in (
        "box_", "decode", "payload", "encoding", "descriptor", "numeric_",
        "fallback", "wide_", "is_row", "integer_tag", "integer_box",
        "signed_from_bits", "width_mask", "pointer", "try_dispatch",
        "known_tag",
    )):
        flags.append("internal")
    return flags or ["binding"]


def inventory(stage: Path) -> dict:
    symbols = load(stage)
    files = library_files()
    bindings = session_bindings(files)
    tiers = ledger("docs/library-api-tiers.txt")
    visibility = ledger("docs/library-manifest.txt")
    rows, warnings = {}, []
    for path in sorted((ROOT / "lib").glob("*.x")):
        if path.name == "x2c.x":
            continue
        relative = path.relative_to(ROOT).as_posix()
        for item in definitions_for_path(path):
            owner, dot, method = item.name.partition(".")
            if owner not in TYPES or not dot or method.startswith("_"):
                continue
            key = relative, item.name, item.signature
            rows[key] = dict(name=item.name, signature=item.signature,
                             path=relative, line=item.line,
                             origin="source or unit macro")
    # Protocol/class methods and foreign aliases can lack a source definition.
    authored = {row["name"].replace(".", "_") for row in rows.values()}
    generated = set()
    for path in symbols.paths():
        if not path.startswith("lib/"):
            continue
        for native, signature in symbols.functions(path).items():
            owner, sep, method = native.partition("_")
            if owner not in TYPES or not sep or method.startswith("_"):
                continue
            key = native, signature.returns, signature.params
            if native in authored or key in generated:
                continue
            generated.add(key)
            name = f"{owner}.{method}"
            declaration = (f"{signature.returns} {name}("
                           f"{', '.join(signature.params) or 'void'})")
            rows[path, name, declaration] = dict(
                name=name, signature=declaration, path=path, line=None,
                origin="generated or foreign interface")
    for row in rows.values():
        path, name = row["path"], row["name"]
        native = name.replace(".", "_")
        row["tier"] = tiers.get((path, name), "primary" if row["line"]
                                else "unclassified generated")
        row["visibility"] = visibility.get(path, "unclassified")
        row["binding"] = bindings.get(native, [])
        row["call"] = name + "(...)"
        row["state"] = "bound, unverified" if row["binding"] else "no binding found"
        row["considerations"] = classify(row)
        row["evidence"] = []
        if path not in symbols.paths() or native not in symbols.functions(path):
            warnings.append(f"{name}: no matching callable in {path}'s interface")
        elif row["line"]:
            entry = symbols.functions(path)[native]
            returns, _, params = split_signature(row["signature"])
            owner = name.split(".", 1)[0]
            returns = re.sub(r"\bSelf\b", owner, returns)
            params = tuple(_strip_param_name(re.sub(r"\bSelf\b", owner, p))
                           for p in params)
            params = tuple(p for p in params if p)
            if (_unqualified(returns) != _unqualified(entry.returns) or
                tuple(map(normalize_type, params)) !=
                    tuple(map(normalize_type, entry.params))):
                warnings.append(f"{name}: source/interface signature mismatch")
    paths = sorted({row["path"] for row in rows.values()})
    for path in paths:
        if path in symbols.paths() and content_hash((ROOT / path).read_bytes()) != symbols.file_hash(path):
            warnings.append(f"{path}: source differs from the stage interface")
    paths += ["tools/meta-api-coverage.py", "docs/library-api-tiers.txt",
              "docs/library-manifest.txt"] + files + ["src/macros.x", "src/comptime.x", "src/expressions.x",
                     "src/parse.x", "src/type.x", "lib/lisp.x"]
    digest = hashlib.sha256()
    for path in sorted(set(paths)):
        digest.update(path.encode())
        digest.update((ROOT / path).read_bytes())
    return dict(
        fingerprint=digest.hexdigest(), layers=files, warnings=warnings,
        rows=sorted(rows.values(), key=lambda row: (TYPES.index(
            row["name"].split(".")[0]), row["name"], row["path"],
            row["signature"])), probes_run=False,
    )


def probe(report: dict, compiler: Path) -> None:
    """Only the fixed inert cases above execute; never synthesize calls."""
    report["probes_run"] = True
    counts = Counter(row["name"] for row in report["rows"])
    report["compiler_sha256"] = hashlib.sha256(compiler.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix="x2c-meta-api-") as directory:
        work = Path(directory)
        for key, (case, body, expected) in PROBES.items():
            name = key.split("#", 1)[0]
            source, binary = work / "probe.x", work / "probe"
            template = ('#include "x2c.x"\n'
                        f'int audit_probe(void) {{ {body} }}\n'
                        'int main(void) { printf("%d\\n", '
                        'audit_probe()); return 0; }\n')
            evidence = dict(case=case, body=body, expected=str(expected))
            try:
                def build(text):
                    source.write_text(text)
                    return subprocess.run(
                        [str(compiler), "build", "--output", str(binary),
                         str(source)], cwd=work, env=os.environ | {
                             "X2C_HOME": str(ROOT)}, capture_output=True,
                        text=True, timeout=30,
                    )

                native = build(template)
                evidence["native_compile_status"] = native.returncode
                if native.returncode:
                    evidence["diagnostic"] = "native control did not compile: " + (
                        native.stdout + native.stderr).replace(str(work), "<probe>").strip()
                    for row in report["rows"]:
                        if row["name"] == name and counts[name] == 1:
                            row["evidence"].append(evidence)
                    continue
                native_run = subprocess.run([str(binary)], capture_output=True,
                                            text=True, timeout=5)
                evidence["native_output"] = native_run.stdout.strip()
                if native_run.returncode or native_run.stdout.strip() != str(expected):
                    evidence["diagnostic"] = "native control did not produce the expected result"
                    for row in report["rows"]:
                        if row["name"] == name and counts[name] == 1:
                            row["evidence"].append(evidence)
                    continue
                built = build(template.replace("int audit_probe", "meta int audit_probe")
                              .replace("audit_probe());", "$audit_probe());"))
                evidence["compile_status"] = built.returncode
                if built.returncode:
                    evidence["diagnostic"] = (built.stdout + built.stderr).replace(
                        str(work), "<probe>").strip()
                else:
                    ran = subprocess.run([str(binary)], capture_output=True,
                                         text=True, timeout=5)
                    evidence.update(run_status=ran.returncode,
                                    output=ran.stdout.strip(),
                                    diagnostic=ran.stderr.strip())
            except subprocess.TimeoutExpired:
                evidence["diagnostic"] = "probe exceeded its time limit"
            okay = (evidence.get("compile_status") == 0 and
                    evidence.get("run_status") == 0 and
                    evidence.get("output") == str(expected))
            for row in report["rows"]:
                if row["name"] == name and counts[name] == 1:
                    row["evidence"].append(evidence)
                    if not okay or row["state"] != "reproduced failure":
                        row["state"] = "verified example" if okay else "reproduced failure"


def markdown(report: dict) -> str:
    lines = [
        "<!-- Generated by tools/meta-api-coverage.py. -->",
        "# Meta API coverage", "",
        "This inventory covers every non-static, non-underscore callable on",
        "String, List, Array, Map, Symbol and Var in the runtime sources and",
        "stage interfaces. It includes generated methods, foreign aliases and",
        "optional modules. Module visibility and API tier distinguish supported",
        "user operations from exported internals; neither group is hidden.", "",
        "Run `python3 tools/meta-api-coverage.py --probe --write` after building",
        "the current tree to refresh this report. Omit `--probe` for a source-only",
        "inventory; `--json` emits full signatures, provenance and diagnostics.",
        "This optional command is not a build or publication gate. Each behavioral",
        "case first compiles and runs as native code; an invalid native control",
        "leaves the operation unverified rather than blaming meta execution.", "",
        "The meta case declares `meta int audit_probe(void)` and invokes it as",
        "`$audit_probe()`. The corresponding native control calls `audit_probe()`",
        "without `meta`. Thus the examples exercise ordinary x2c function bodies",
        "and explicit x2c meta-call syntax, not hand-written Lisp calls.", "",
        "## What the states establish", "",
        "A **verified example** establishes only its listed case. A **reproduced",
        "failure** records that case's compilation or execution failure, which",
        "may involve a dependency called by the example. **Bound, unverified**",
        "means the session defines the resolved name; **no binding found** means",
        "the standard loaded files contain no definition of that name. Neither",
        "binding search result is a behavioral test. User-installed bindings can",
        "extend this surface.", "",
        "Bindings are discovered from the compiler's library loader and native",
        "installation. A dotted Lisp name alone does not expose an ordinary",
        "method: that call uses its resolved underscore name. Templates, indexing,",
        "truth tests and conversions can have separate lowering. Their presence",
        "does not imply that a similarly named direct method works.", "",
        "Loaded layers: " + ", ".join(f"`{path}`" for path in report["layers"]) + ".",
        "", "Source fingerprint: `" + report["fingerprint"] + "`.", "",
    ]
    if report["probes_run"]:
        lines += ["Compiler fingerprint: `" + report["compiler_sha256"] + "`.", ""]
    else:
        lines += ["No behavioral probes were run for this report.", ""]
    if report["warnings"]:
        lines += ["### Interface discrepancies", ""]
        lines += ["- " + warning for warning in report["warnings"]]
        lines += [""]
    lines += ["| Type | Callables | Binding found | No binding found |",
              "| --- | ---: | ---: | ---: |"]
    for owner in TYPES:
        rows = [r for r in report["rows"] if r["name"].startswith(owner + ".")]
        found = sum(bool(r["binding"]) for r in rows)
        lines += [f"| {owner} | {len(rows)} | {found} | {len(rows) - found} |"]
    lines += ["", "## What a missing operation may need", "",
              "These are contract and signature considerations, not claims about",
              "why an operation was historically omitted. Multiple considerations",
              "can apply. No label promises that adding an alias is sufficient.", ""]
    lines += [f"- **{name}:** {text}" for name, text in CONSIDERATIONS.items()]
    lines += ["", "The existing adapters also merge runtime `void` with an empty",
              "List. Missing values, null arguments, callbacks and ownership need",
              "explicit checks before claiming runtime equivalence.", ""]
    for owner in TYPES:
        rows = [r for r in report["rows"] if r["name"].startswith(owner + ".")]
        lines += [f"## {owner}", ""]
        for state in STATES:
            names = [r["name"].split(".", 1)[1] for r in rows if r["state"] == state]
            if names:
                lines += [f"**{state}:** " + ", ".join(f"`{n}`" for n in names) + ".", ""]
        lines += ["| Direct callable | State | Binding provenance | Considerations | Tier/module | Source |",
                  "| --- | --- | --- | --- | --- | --- |"]
        for row in rows:
            source = row["path"] + (f":{row['line']}" if row["line"] else " (interface)")
            provenance = "; ".join(row["binding"]) or "none found"
            lines += [f"| `{row['signature']}` | {row['state']} | {provenance} | "
                      f"{', '.join(row['considerations'])} | {row['tier']}/{row['visibility']} | {source} |"]
        cases = [r for r in rows if r["evidence"]]
        if cases:
            lines += ["", "### Evaluated cases", ""]
            for row in cases:
                for evidence in row["evidence"]:
                    result = (f"returned {evidence['output']}" if
                              evidence.get("output") == evidence["expected"] and
                              evidence.get("run_status") == 0 else
                              evidence.get("diagnostic") or
                              f"returned {evidence.get('output')}, expected {evidence['expected']}")
                    if "\n" in result:
                        notes = [line.strip() for line in result.splitlines()
                                 if "reason:" in line or ": error:" in line]
                        result = "; ".join(notes) or result.splitlines()[0]
                    lines += [f"- `{row['name']}`: {evidence['case']}; {result}."]
        lines += [""]
    lines += ["## Remaining evidence gaps", "",
              "Unlisted argument combinations, every callback signature, native",
              "pointer interoperability, resource lifetimes and optional-module",
              "effects remain unverified. The fixed probes do not exercise file or",
              "process operations or transfer ownership of evaluator objects.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, default=ROOT / "builds/0")
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    if args.json and args.write:
        parser.error("--json writes to stdout; --write writes the Markdown report")
    try:
        report = inventory(args.stage.resolve())
        if args.probe:
            probe(report, args.stage.resolve() / "x2c")
        output = json.dumps(report, indent=2) if args.json else markdown(report)
        if args.write:
            REPORT.write_text(output)
            print(f"wrote {REPORT.relative_to(ROOT)}")
        else:
            print(output)
        return 0
    except (OSError, ValueError) as error:
        print(f"meta-api-coverage: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
