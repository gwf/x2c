"""Independently recount the pinned source-size corpus without building it."""
from pathlib import Path
import csv
import gzip
import hashlib
import io
import json
import math
import re
import statistics
import subprocess
import tokenize

REPO = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], cwd=Path(__file__).resolve().parent, text=True).strip())
REVISION = "36c17924d0c8980c57aa1e9cd661e5c9d5ac3caf"
RUN = "20261101T161913Z"
OUTPUT = REPO / "debug/plso-regex-20261101/source-size-audit.json"
SHARED = ["nbody", "spectralnorm", "fannkuchredux", "mandelbrot", "fasta", "revcomp", "regexredux", "pidigits"]
FILENAMES = {"c": "main.c", "rust": "main.rs", "idiomatic": "main.x", "tuned": "tuned.x", "cpp": "main.cpp", "go": "main.go", "java": "main.java", "python": "main.py"}

# This tokenizer uses protected-literal regex alternatives, not the harness's
# character-by-character state machine. A character literal has one character
# or escape, so Rust lifetimes do not capture later quoted text. Escapes may
# include a newline; this preserves Rust's multiline sequence literal.
STRING = r'"(?:\\[\s\S]|[^"\\])*"'
CHARACTER = r"'(?:\\[\s\S]|[^'\\])'"
LITERAL = "(?:" + STRING + "|" + CHARACTER + ")"
def normalize_segments(clean, literal_spans):
    output = []
    cursor = 0
    for start, end in literal_spans:
        output.append(re.sub(r"\s+", " ", clean[cursor:start]))
        output.append(clean[start:end])
        cursor = end
    output.append(re.sub(r"\s+", " ", clean[cursor:]))
    return "".join(output).strip().encode()


def python_source(text):
    # Replace comment characters with spaces at their original positions.
    # Tokenize identifies complete Python literals, including prefixes and
    # triple quotes; this does not use the harness's untokenize replacement.
    lines = text.splitlines(keepends=True)
    offsets = [0]
    for line in lines:
        offsets.append(offsets[-1] + len(line))
    chars = list(text)
    literals = []
    for token in tokenize.generate_tokens(io.StringIO(text).readline):
        start = offsets[token.start[0] - 1] + token.start[1]
        end = offsets[token.end[0] - 1] + token.end[1]
        if token.type == tokenize.COMMENT:
            chars[start:end] = " " * (end - start)
        elif token.type == tokenize.STRING:
            literals.append((start, end))
    return "".join(chars), literals


def c_like_source(text, mode):
    literal = LITERAL + (r"|`[^`]*`" if mode == "go" else "")
    if mode == "cpp":
        literal = r'R"\([\s\S]*?\)"|' + literal
    tokens = re.compile(literal + r"|//[^\n]*|/\*[\s\S]*?\*/")
    clean = tokens.sub(lambda match: "\n" * match[0].count("\n")
        if match[0].startswith(("//", "/*")) else match[0], text)
    spans = [(match.start(), match.end()) for match in re.finditer(literal, clean)]
    return clean, spans


def metrics(text, mode):
    clean, literals = python_source(text) if mode == "python" else c_like_source(text, mode)
    normalized = normalize_segments(clean, literals)
    return {
        "source_lines": sum(bool(line.strip()) for line in clean.splitlines()),
        "game_style_gzip_bytes": len(gzip.compress(normalized, compresslevel=1, mtime=0)),
        "normalized_bytes": len(normalized),
        "normalized_sha256": hashlib.sha256(normalized).hexdigest(),
    }


def main():
    chart = REPO / f"examples/shootout/results/runs/{RUN}/charts/measurements.csv"
    with chart.open() as file:
        rows = list(csv.DictReader(file))
    audited = []
    literal_probes = []
    supported_forms = []
    for row in rows:
        mode = row["implementation"]
        if mode not in FILENAMES:
            continue
        path = f"examples/shootout/benchmarks/{row['problem']}/{FILENAMES[mode]}"
        source = subprocess.check_output(["git", "show", REVISION + ":" + path], cwd=REPO)
        text = source.decode()
        unsupported = []
        checks = {
            "cpp": [("C++ raw string", r'\b(?:u8|u|U|L)?R"[^ \t\r\n()\\]{0,16}\(')],
            "rust": [("Rust raw string", r'\b(?:br|r)\#*"')],
            "java": [("Java text block", r'"""')],
        }
        for label, pattern in checks.get(mode, []):
            if re.search(pattern, text):
                if mode == "cpp":
                    raw = re.findall(r'\b(?:u8|u|U|L)?R"([^ \t\r\n()\\]{0,16})\(', text)
                    if all(delimiter == "" for delimiter in raw):
                        supported_forms.append({"path": path, "form": "C++ raw string", "delimiter": "", "count": len(raw), "status": "Explicit empty-delimiter raw-literal regex protects the full literal."})
                    else:
                        unsupported.append(label)
                else:
                    unsupported.append(label)
        if mode == "rust":
            # No nested block comment occurs in the pinned Rust corpus.
            for comment in re.finditer(r"/\*[\s\S]*?\*/", text):
                if "/*" in comment[0][2:]:
                    unsupported.append("nested Rust block comment")
        if unsupported:
            literal_probes.append({"path": path, "unsupported_forms": unsupported})
        actual = metrics(text, mode)
        expected = {"source_lines": int(row["source_lines"]), "game_style_gzip_bytes": int(row["gzip_bytes"])}
        audited.append({"problem": row["problem"], "implementation": mode, "path": path,
            "source_sha256": hashlib.sha256(source).hexdigest(), "harness": expected,
            "independent": actual, "matches": all(actual[key] == value for key, value in expected.items())})
    lookup = {(row["problem"], row["implementation"]): row["independent"] for row in audited}
    aggregates = {}
    for mode in ["idiomatic", "tuned"]:
        for baseline in ["c", "rust"]:
            aggregates[mode + "_over_" + baseline] = {
                metric: math.exp(statistics.mean(math.log(lookup[name, mode][metric] / lookup[name, baseline][metric]) for name in SHARED))
                for metric in ["source_lines", "game_style_gzip_bytes"]}
    result = {
        "revision": REVISION, "comparison_run": RUN, "shared_workloads": SHARED,
        "audited_program_count": len(audited), "mismatch_count": sum(not row["matches"] for row in audited),
        "method": "C-like languages: independent regex-based protected string/character tokenization (plus Go backticks and the observed empty-delimiter C++ raw string), preserving comment newlines. Python: tokenize discovers COMMENT/STRING source spans, comments are replaced in place with spaces and complete literals preserved. Independent nonliteral whitespace collapse and gzip level 1 with mtime=0 follow. Does not import or call harness stripping/normalization or Python untokenize.",
        "scope": "All 75 admitted programs: 20 x2c, 10 C, and 9 each Rust/C++/Go/Java/Python. Sources are read from pinned Git objects, not the changing working tree. The original 39-program C/Rust/x2c evidence remains as a named subset.",
        "limits": "A corpus audit, not a general-purpose lexer proof. Nested Rust block comments, arbitrary Rust raw-string forms, nonempty-delimiter C++ raw strings, Java text blocks and multicharacter C character literals are outside the C-like tokenizer supported forms. One empty-delimiter C++ raw string occurs in regex-redux and is explicitly protected; no unsupported literal form was observed in the pinned admitted corpus. Python uses standard tokenizer spans, including complete multiline literals; Go backticks are supported.",
        "metric_definition": "LOC means nonblank physical lines after comment removal; it depends on formatting. Gzip means bytes after comment removal and whitespace collapse outside literals, gzip level 1. Both describe contribution-file source, excluding imported library implementations and generated code. Neither measures semantic complexity.",
        "aggregate_ratios": aggregates,
        "findings": [
            "The chart does not show C shorter by LOC overall: tuned x2c/C is 0.950x LOC. It does show tuned x2c larger in normalized gzip bytes: 1.142x.",
            "Idiomatic x2c/C is 0.849x LOC and 1.014x gzip; tuned x2c/Rust is 0.763x LOC and 0.840x gzip.",
            "Geometric-mean ratios use the same eight workload cohort. The chart normalizes each workload to its shortest/smallest admitted contribution before aggregation; dividing the two implementation coordinates cancels those common denominators.",
            "The audited counts match exactly. Source size and compressed size can disagree because identifiers, repeated tokens, numeric literals, formatting and helper definitions compress differently."
        ],
        "verbosity_owners": [
            {"path": "examples/shootout/benchmarks/pidigits/tuned.x", "lines": "36-64", "evidence": "Nine private Integer constructor/lifecycle/operation forwarders plus repeated state initialization and cleanup. Tuned has 81 LOC/917 gzip bytes versus C's 45/444.", "recommendation": "Remove the Integer layer and call GMP inside the existing Spigot owner. Keep both extracts, cleanup, partial-line padding and variant-specific fused operations. Private handoff 3dce68a939129200b9a1605aee19474024fee47f does this; root owns executable verification."},
            {"path": "examples/shootout/benchmarks/spectralnorm/tuned.x", "lines": "45-123", "evidence": "Explicit Thread scheduling and four serial/banded A/At kernels: 104 LOC/855 gzip bytes versus C's 54/459. C uses OpenMP pragmas to express scheduling.", "recommendation": "Keep the measured serial specialization. Earlier delegation to banded kernels lost 9-11%; try a new specialization approach only with fresh performance evidence."},
            {"path": "examples/shootout/benchmarks/fannkuchredux/tuned.x", "lines": "22-61", "evidence": "Explicit chunk records, Thread startup/join and initialization versus C's OpenMP loop: tuned 100 LOC/1022 bytes, C 86/900.", "recommendation": "Review assignment-only initialization and scheduling repetition; avoid line golfing or changing scheduling solely to shrink counts."},
            {"path": "examples/shootout/results/reference-coverage.md", "lines": "102-104", "evidence": "C pidigits omits final partial-group count, while x2c retains padded final groups. C also does not clear its process-lifetime GMP values; x2c releases its owned values.", "recommendation": "Do not remove behavior or cleanup to match C's source size."}
        ],
        "unsupported_literal_forms_probe": literal_probes,
        "supported_literal_forms_probe": supported_forms,
        "programs": audited,
    }
    original = [row for row in audited if row["implementation"] in ["c", "rust", "idiomatic", "tuned"]]
    result["original_c_rust_x2c_audit"] = {
        "revision": REVISION, "program_count": len(original),
        "mismatch_count": sum(not row["matches"] for row in original),
        "paths": [row["path"] for row in original],
        "preservation": "Every old source SHA, expected LOC/gzip, independent LOC/gzip and normalized-source SHA is retained in programs. The tokenizer implementation is generalized without changing original-corpus results."
    }
    result["language_counts"] = {mode: sum(row["implementation"] == mode for row in audited) for mode in FILENAMES}
    assert len(audited) == 75 and len(original) == 39 and result["mismatch_count"] == 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(result, indent=2) + "\n")
    print(f"{len(audited)} programs, zero count mismatches: {OUTPUT}")


if __name__ == "__main__":
    main()
