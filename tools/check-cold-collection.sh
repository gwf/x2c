#!/usr/bin/env bash
# Retranslate lib/ and src/ with the stage 1 compiler, reading no .xi
# interface, and require stage 2's C, headers, and interfaces byte for byte.
# A stage build replays interfaces from its own library batch and from the
# previous stage, so a difference means warm replay and a cold walk collect
# different declarations.
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ ! -x builds/1/x2c || ! -d builds/2/src ]]; then
  echo "cold collection check: build stage 2 first" >&2
  exit 2
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/lib" "$scratch/src"
# Generated C records each source path as given, so translate from the stage
# directory with the stage build's spellings.
(
  cd builds/2
  ../1/x2c translate -q --no-interfaces --out-dir "$scratch/lib" ../../lib/*.x
  ../1/x2c translate -q --no-interfaces --out-dir "$scratch/src" ../../src/*.x
)
./tools/check-generated-stages.sh --interfaces builds/2 "$scratch"
