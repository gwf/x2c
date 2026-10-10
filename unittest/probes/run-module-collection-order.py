#!/usr/bin/env python3
"""Compare real linked-meta output before and after module collection."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("compiler", type=Path)
args = parser.parse_args()
compiler = args.compiler.resolve()
root = Path(__file__).resolve().parents[2]
scratch = Path(tempfile.mkdtemp(prefix="x2c-module-collection-order-", dir="/tmp"))
identity = hashlib.sha256(compiler.read_bytes()).hexdigest()
results = []
for label, inputs in (
        ("alone", ["src/linked-meta.x"]),
        ("after-module", ["src/macros.x", "src/linked-meta.x"])):
    output = scratch / label
    output.mkdir()
    command = [str(compiler), "translate", "-j", "1", "--no-interfaces",
               "--out-dir", str(output), *inputs]
    process = subprocess.run(command, cwd=root, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (scratch / (label + ".log")).write_text(process.stdout)
    results.append({"label": label, "command": command,
                    "status": process.returncode})
equal = all(row["status"] == 0 for row in results)
compared = {}
if equal:
    for suffix in (".c", ".h", ".xi"):
        name = "linked-meta" + suffix
        compared[name] = (scratch / "alone" / name).read_bytes() == (
            scratch / "after-module" / name).read_bytes()
    equal = all(compared.values())
unchanged = identity == hashlib.sha256(compiler.read_bytes()).hexdigest()
(scratch / "results.json").write_text(json.dumps({
    "compiler": str(compiler), "compiler_sha256": identity,
    "compiler_unchanged": unchanged, "runs": results,
    "compared": compared, "passed": equal and unchanged}, indent=2) + "\n")
print(("PASS" if equal and unchanged else "FAIL") + " module collection order; " +
      str(scratch / "results.json"))
raise SystemExit(0 if equal and unchanged else 1)
