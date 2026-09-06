#!/usr/bin/env python3
"""Find explicit x2c conversions whose removal emits identical C.

Each candidate is removed by itself in an isolated copy of the current
tracked tree.  A call is reported only when translation still succeeds and
the compiler's complete --dump-code output is byte-identical.
"""

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile


SIGNATURE = re.compile(
    r"(?m)^[ \t]*(?:(?:static|inline|extern|threaded)\s+)*"
    r"([A-Za-z_][A-Za-z0-9_]*)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)"
    r"\s*\(([^()]*)\)\s*(?:\{|;)"
)
CALL = re.compile(r"\.([a-z_][A-Za-z0-9_]*)\s*\(\s*\)")


def run(args, cwd, **kwargs):
    return subprocess.run(args, cwd=cwd, **kwargs)


def tracked_copy(source, destination):
    result = run(
        ["git", "ls-files", "-z"], source, check=True,
        stdout=subprocess.PIPE,
    )
    for raw in result.stdout.split(b"\0"):
        if not raw:
            continue
        relative = pathlib.Path(raw.decode())
        origin = source / relative
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if origin.is_symlink():
            target.symlink_to(origin.readlink())
        else:
            shutil.copy2(origin, target)


def install_compiler(source, destination, requested):
    if requested:
        compiler = pathlib.Path(requested).resolve()
    else:
        compiler = source / "bin" / "x2c-bootstrap"
    if not compiler.is_file():
        raise SystemExit(f"compiler not found: {compiler}")
    target = destination / "bin" / "x2c-audit"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(compiler, target)
    return pathlib.Path("bin/x2c-audit")


def source_mask(source):
    masked = list(source)
    i = 0
    while i < len(source):
        if source.startswith("//", i):
            end = source.find("\n", i)
            end = len(source) if end < 0 else end
            masked[i:end] = " " * (end - i)
            i = end
        elif source.startswith("/*", i):
            end = source.find("*/", i + 2)
            end = len(source) - 2 if end < 0 else end
            for j in range(i, end + 2):
                if masked[j] != "\n":
                    masked[j] = " "
            i = end + 2
        elif source[i] in "\"'":
            quote = source[i]
            i += 1
            while i < len(source):
                if source[i] == "\\":
                    if masked[i] != "\n":
                        masked[i] = " "
                    if i + 1 < len(source) and masked[i + 1] != "\n":
                        masked[i + 1] = " "
                    i += 2
                elif source[i] == quote:
                    i += 1
                    break
                else:
                    if masked[i] != "\n":
                        masked[i] = " "
                    i += 1
        else:
            i += 1
    return "".join(masked)


def converter_methods(files):
    methods = {"pointer"}
    for path in files:
        source = path.read_text(errors="ignore")
        for match in SIGNATURE.finditer(source):
            result, receiver, method, parameters = match.groups()
            params = [p.strip() for p in parameters.split(",")
                      if p.strip() and p.strip() != "void"]
            receiver_parameter = (
                len(params) == 1 and
                re.match(
                    rf"^(?:const\s+)?{re.escape(receiver)}"
                    rf"(?:\s+|\s*\*\s*)[A-Za-z_]",
                    params[0],
                )
            )
            named_conversion = (
                method == result.lower() or
                (result == "String" and method == "str") or
                (receiver == "Var" and result == "long" and
                 method == "integer")
            )
            if receiver_parameter and named_conversion:
                methods.add(method)
    return methods


def call_kind(source, start):
    line_start = source.rfind("\n", 0, start) + 1
    prefix = source[line_start:start]
    if re.search(r"\breturn\b", prefix):
        return "return"
    declaration = re.match(
        r"^\s*(?:(?:const|static|inline|extern|threaded|unsigned|signed|"
        r"long|short)\s+)*[A-Za-z_][A-Za-z0-9_]*"
        r"(?:\s*\*+\s*|\s+)[A-Za-z_][A-Za-z0-9_]*\s*=",
        prefix,
    )
    if declaration:
        return "declaration"
    if "=" in prefix and not re.search(r"(?:==|!=|<=|>=)\s*$", prefix):
        return "assignment"
    return "argument"


def translate(root, compiler, relative):
    return run(
        [str(compiler), "translate", "--plain", "--dump-code",
         str(relative)],
        root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )


def audit(root, compiler, files, methods):
    results = []
    failed_files = {}
    for relative in files:
        path = root / relative
        source = path.read_text(errors="ignore")
        matches = [m for m in CALL.finditer(source_mask(source))
                   if m.group(1) in methods]
        if not matches:
            continue
        baseline = translate(root, compiler, relative)
        if baseline.returncode:
            failed_files[str(relative)] = baseline.stderr.splitlines()[-4:]
            continue
        for match in matches:
            changed = source[:match.start()] + source[match.end():]
            path.write_text(changed)
            candidate = translate(root, compiler, relative)
            path.write_text(source)
            if candidate.returncode or candidate.stdout != baseline.stdout:
                continue
            line = source.count("\n", 0, match.start()) + 1
            line_start = source.rfind("\n", 0, match.start()) + 1
            line_end = source.find("\n", match.end())
            if line_end < 0:
                line_end = len(source)
            results.append({
                "file": str(relative),
                "line": line,
                "method": match.group(1),
                "kind": call_kind(source, match.start()),
                "start": match.start(),
                "end": match.end(),
                "text": source[line_start:line_end].strip(),
            })
    return results, failed_files


def verify_together(root, compiler, results, failed_files):
    by_file = {}
    for result in results:
        by_file.setdefault(result["file"], []).append(result)
    verified = []
    for name, changes in by_file.items():
        relative = pathlib.Path(name)
        path = root / relative
        source = path.read_text()
        baseline = translate(root, compiler, relative)
        changed = source
        for change in sorted(changes, key=lambda item: item["start"],
                             reverse=True):
            changed = changed[:change["start"]] + changed[change["end"]:]
        path.write_text(changed)
        combined = translate(root, compiler, relative)
        path.write_text(source)
        if combined.returncode or combined.stdout != baseline.stdout:
            failed_files[name] = [
                "individually identical removals differed when combined"
            ]
            continue
        verified.extend(changes)
    return verified


def rewrite(source_root, results):
    by_file = {}
    for result in results:
        by_file.setdefault(result["file"], []).append(result)
    for relative, changes in by_file.items():
        path = source_root / relative
        source = path.read_text()
        for change in sorted(changes, key=lambda item: item["start"],
                             reverse=True):
            call = source[change["start"]:change["end"]]
            expected = f'.{change["method"]}()'
            if re.sub(r"\s+", "", call) != expected:
                raise SystemExit(f"source changed during audit: {relative}")
            source = source[:change["start"]] + source[change["end"]:]
        path.write_text(source)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths", nargs="*", default=["src", "lib", "examples"],
        help="files or directories to audit",
    )
    parser.add_argument("--apply", action="store_true",
                        help="remove every byte-identical call found")
    parser.add_argument("--compiler", help="x2c executable to copy")
    parser.add_argument("--json", type=pathlib.Path,
                        help="write the complete result as JSON")
    args = parser.parse_args()

    source_root = pathlib.Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="x2c-conversion-audit-") as tmp:
        root = pathlib.Path(tmp)
        tracked_copy(source_root, root)
        compiler = install_compiler(source_root, root, args.compiler)
        files = []
        for name in args.paths:
            path = root / name
            if path.is_dir():
                files.extend(path.rglob("*.x"))
            elif path.suffix == ".x":
                files.append(path)
        relative_files = sorted({path.relative_to(root) for path in files})
        methods = converter_methods(
            path for base in (root / "src", root / "lib")
            for path in base.rglob("*.x")
        )
        results, failures = audit(root, compiler, relative_files, methods)
        results = verify_together(root, compiler, results, failures)

    payload = {
        "methods": sorted(methods),
        "results": results,
        "failed_files": failures,
    }
    if args.json:
        args.json.write_text(json.dumps(payload, indent=2) + "\n")
    for result in results:
        print(f'{result["file"]}:{result["line"]}\t{result["kind"]}'
              f'\t.{result["method"]}()\t{result["text"]}')
    print(f"exact={len(results)} failed_files={len(failures)}",
          file=sys.stderr)
    if args.apply:
        rewrite(source_root, results)
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
