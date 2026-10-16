#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd -P)
X2C="$ROOT/builds/0/x2c"
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/x2c-new-test.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM

# A new project runs as written, and new never writes into a used directory.
starter="$BUILD/starter/hello"
"$X2C" new -q "$starter"
(cd "$starter" && [ "$("$X2C" run -q -- x2c)" = "Hello, x2c!" ])
cp "$starter/x2c.toml" "$BUILD/starter/x2c.toml.before"
set +e
"$X2C" new "$starter" 2>"$BUILD/starter/again.stderr"
starter_status=$?
set -e
[ "$starter_status" = 2 ] || exit 1
grep -Fq "exists and is not an empty directory" "$BUILD/starter/again.stderr"
cmp "$BUILD/starter/x2c.toml.before" "$starter/x2c.toml"

# An empty operand names no directory, and a link names itself.
set +e
(cd "$starter" && "$X2C" new "") 2>"$BUILD/starter/empty.stderr"
empty_status=$?
set -e
[ "$empty_status" = 2 ] || exit 1
grep -Fq "the directory operand is empty" "$BUILD/starter/empty.stderr"
cmp "$BUILD/starter/x2c.toml.before" "$starter/x2c.toml"
mkdir -p "$BUILD/starter/real-name"
ln -s real-name "$BUILD/starter/link-name"
"$X2C" new -q "$BUILD/starter/link-name"
grep -Fxq '[target.link-name]' "$BUILD/starter/real-name/x2c.toml"

