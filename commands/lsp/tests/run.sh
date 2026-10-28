#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd -P)
SERVER="$ROOT/builds/0/libexec/x2c-lsp"
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/x2c-lsp-test.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
export X2C_CACHE_DIR="$BUILD/cache"
printf 'int disk_only(void);\n' > "$BUILD/input.x"
frame() {
  printf '%s' "$1" > "$BUILD/body"
  printf 'Content-Length: %s\r\n\r\n' "$(wc -c < "$BUILD/body" | tr -d ' ')"
  cat "$BUILD/body"
}
{
  frame '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
  frame '{"jsonrpc":"2.0","method":"initialized","params":{}}'
  frame '{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file://'"$BUILD"'/input.x","languageId":"x2c","version":1,"text":"int value(void);\nint call(void) { return value(); }\n"}}}'
  frame '{"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://'"$BUILD"'/input.x"},"position":{"line":1,"character":25}}}'
  frame '{"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://'"$BUILD"'/input.x"},"position":{"line":1,"character":25}}}'
  frame '{"jsonrpc":"2.0","id":4,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$SERVER" > "$BUILD/replies" 2> "$BUILD/stderr"
grep -q '"id":1' "$BUILD/replies"
grep -q '"hoverProvider":true' "$BUILD/replies"
grep -q '"id":2' "$BUILD/replies"
grep -q 'int value(void);' "$BUILD/replies"
grep -q '"id":3' "$BUILD/replies"
grep -q '"uri":"file://.*/input.x"' "$BUILD/replies"
grep -q '"id":4,"jsonrpc":"2.0","result":null' "$BUILD/replies"
# JSON parse failures leave the following frame readable.
{
  frame '{'
  frame '{"jsonrpc":"2.0","id":10,"method":"initialize","params":{}}'
  frame '{"jsonrpc":"2.0","id":11,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} | "$SERVER" > "$BUILD/errors" 2> "$BUILD/error-stderr"
grep -q '"code":-32700' "$BUILD/errors"
grep -q '"id":10' "$BUILD/errors"
# Cancellation is drained before a queued semantic request begins.
{
  frame '{"jsonrpc":"2.0","id":20,"method":"initialize","params":{}}'
  frame '{"jsonrpc":"2.0","id":21,"method":"textDocument/hover","params":{}}'
  frame '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":21}}'
  frame '{"jsonrpc":"2.0","id":22,"method":"shutdown"}'
  frame '{"jsonrpc":"2.0","method":"exit"}'
} > "$BUILD/cancel-input"
"$SERVER" < "$BUILD/cancel-input" > "$BUILD/cancel" 2> "$BUILD/cancel-stderr"
grep -q '"code":-32800.*"id":21' "$BUILD/cancel"
printf '%s\n' 'language server smoke tests passed'

python3 "$ROOT/commands/lsp/tests/protocol.py" "$ROOT"
