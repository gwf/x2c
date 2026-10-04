#!/usr/bin/env bash
# Retranslate lib/ and src/ with the stage 0 compiler, reading no .xi
# interface, and require stage 1's C, headers, and interfaces byte for byte.
# A stage build replays interfaces from its own library batch and from the
# previous stage, so a difference means warm replay and a cold walk collect
# different declarations.
set -euo pipefail

cd "$(dirname "$0")/.."
if [[ ! -x builds/0/x2c || ! -d builds/1/src ]]; then
  echo "cold collection check: build stage 1 first" >&2
  exit 2
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir "$scratch/lib" "$scratch/src"
# Generated C records each source path as given, so translate from the stage
# directory with the stage build's spellings. Neither translation reads the
# other's output, so they run at once as parallel jobs, which an interrupt
# stops whole; under Make, x2c defaults to one job, so pass the outer build's
# job count.
(
  cd builds/1
  translate() {
    ../0/x2c translate ${BUILD_JOBS:+-j "$BUILD_JOBS"} -q --no-interfaces \
      --out-dir "$scratch/$1" ../../"$1"/*.x
  }
  . ../../commands/parallel.sh
  parallel_start lib translate lib
  parallel_start src translate src
  parallel_wait
)
./tools/check-generated-stages.sh --interfaces builds/1 "$scratch"
