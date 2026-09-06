#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SDK_ROOT=$("$SCRIPT_DIR/setup-toolchain.sh")

COSMOCC=$SDK_ROOT/cosmocc/bin/cosmocc
COSMOAR=$SDK_ROOT/cosmocc/bin/cosmoar
COSMO_LICENSE_DIR=$SDK_ROOT/cosmocc

export COSMOCC COSMOAR
export COSMO_LICENSE_DIR

exec "$SCRIPT_DIR/build-ape.sh"
