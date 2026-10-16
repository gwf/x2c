#!/bin/sh
set -eu
cd "$(dirname "$0")/../../.."
exec bash unittest/probes/run-package-install.sh
