#!/usr/bin/env bash
# Print the BLIS profile for the current platform as JSON.
#
#   tools/record-blis-profile.sh packages/blis/dependency-generic.json
#
# BLIS records its archive member count and the symbols the archive leaves
# undefined, and both follow the kernel set the configuration selects, so a
# profile belongs to one operating system and machine. This prepares the
# pinned dependency and reports what a profile for this platform holds.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
manifest=${1:?usage: record-blis-profile.sh <dependency manifest>}
manifest=$(cd "$(dirname "$manifest")" && pwd)/$(basename "$manifest")

cd "$ROOT/packages/blis"
python3 ../tools/deps.py prepare "$manifest" >&2
prefix=$(python3 ../tools/deps.py path "$manifest" prefix)
archive="$prefix/lib/libblis.a"
[[ -f "$archive" ]] || { echo "missing $archive" >&2; exit 1; }

if [[ $(uname -s) == Darwin ]]; then
  symbol='substr($1, 2)'
else
  symbol='$1'
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/x2c-blis-profile.XXXXXX")
trap 'rm -rf "$work"' EXIT
export LC_ALL=C
nm -g --format=posix "$archive" |
  awk "\$2 == \"U\" {print $symbol}" | sort -u >"$work/undefined"
nm -g --format=posix "$archive" |
  awk "\$2 != \"U\" && NF >= 2 {print $symbol}" | sort -u >"$work/defined"
comm -23 "$work/undefined" "$work/defined" >"$work/external"

python3 - "$prefix" "$manifest" "$work/external" "$archive" <<'PY'
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
    "external_undefined_symbols": open(external).read().split(),
  },
}
print("BEGIN-PROFILE")
print(json.dumps(profile, indent=2))
print("END-PROFILE")
PY
