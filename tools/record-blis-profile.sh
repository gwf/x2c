#!/usr/bin/env bash
# Print the BLIS profile for the current platform as JSON.
#
#   tools/record-blis-profile.sh
#
# BLIS records its archive member count and the symbols the archive leaves
# undefined, and both follow the kernel set the configuration selects, so a
# profile belongs to one operating system and machine. This prepares the
# platform's pinned dependency and reports what a profile for it holds.
set -euo pipefail

cd "$(dirname "$0")/../packages/blis"
manifest=$(python3 ../tools/deps.py manifest .)
python3 ../tools/deps.py prepare "$manifest" >&2
prefix=$(python3 ../tools/deps.py path "$manifest" prefix)
archive="$prefix/lib/libblis.a"
[[ -f "$archive" ]] || { echo "missing $archive" >&2; exit 1; }

external=$(./external-symbols.sh "$archive")

python3 - "$prefix" "$manifest" "$external" "$archive" <<'PY'
import hashlib, json, subprocess, sys

prefix, manifest, external, archive = sys.argv[1:5]
template = json.load(open("PROFILE-linux-x86_64.json"))
header = f"{prefix}/include/blis/blis.h"
# One member per line, as the profile check counts them: the macOS table
# of contents starts with "__.SYMDEF SORTED", which splitting on whitespace
# would count twice.
members = subprocess.run(["ar", "-t", archive], capture_output=True,
                         text=True, check=True).stdout.splitlines()
profile = {
  "schema": template["schema"],
  "upstream": template["upstream"],
  "build": dict(template["build"],
                configuration=json.load(open(manifest))["steps"][0]["argv"][-1]),
  "header_sha256": hashlib.sha256(open(header, "rb").read()).hexdigest(),
  "archive": {
    "members": len(members),
    "external_undefined_symbols": external.split(),
  },
}
print("BEGIN-PROFILE")
print(json.dumps(profile, indent=2))
print("END-PROFILE")
PY
