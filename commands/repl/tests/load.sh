#!/bin/sh
set -eu

cd "$(dirname "$0")/../../.."
tmp=${TMPDIR:-/tmp}/x2c-repl-load.$$
mkdir -p "$tmp"
trap 'status=$?; if test "$status" -ne 0; then cat "$tmp/out" "$tmp/err" >&2; fi; rm -rf "$tmp"' EXIT HUP INT TERM
export X2C_CACHE_DIR="$tmp/cache" TMPDIR="$tmp"

cat >"$tmp/dependency.x" <<'EOF'
#pragma once
int offset(int n) { return n + 1; }
EOF
cat >"$tmp/native.x" <<'EOF'
#include "dependency.x"
#include <stdlib.h>
typedef int Count;
static int double_of(int n) { return 2 * n; }
static int calls = 0;
Count loaded_answer(Count n) { calls++; return double_of(offset(n)); }
int loaded_calls(void) { return calls; }
meta String loaded_text(void) { return "kept native text"; }
meta List loaded_list(void) { return %("kept native list" 42); }
Array loaded_append(Array values) { values.push(99); return values; }
void loaded_exit(void) { exit(9); }
EOF
cat >"$tmp/second.x" <<'EOF'
#include "dependency.x"
enum LoadColor { LOAD_RED = 3 };
enum LoadColor ordinary_color = LOAD_RED;
int second_answer(void) { return offset(LOAD_RED + 1); }
EOF

# Run directly to exercise discovery of the adjacent compiler as well as
# the normal driver dispatch exercised by the edit checks below.
printf '%s\n' 'int before = 7;' \
  'int plus(int x) { return before + x; }' \
  ":load \"$tmp/native.x\"" 'loaded_answer(20);' \
  'loaded_calls();' 'loaded_text();' 'loaded_list();' \
  'Count n = 8;' 'plus(n);' 'Array a = [1];' \
  'loaded_append(a);' 'a.len() == 1;' \
  ":load \"$tmp/second.x\"" 'second_answer();' \
  'loaded_text();' 'loaded_list();' 'loaded_calls();' 'plus(2);' \
  >"$tmp/input"
builds/0/libexec/x2c-repl <"$tmp/input" >"$tmp/out" 2>"$tmp/err"
cat >"$tmp/expected" <<'EOF'
ok
defined plus
loaded ("loaded_text" "loaded_list" "loaded_answer"
 "loaded_calls" "loaded_append" "loaded_exit")
reset all loaded native state
=> 42
=> 1
=> "kept native text"
=> ("kept native list" 42)
ok
=> 15
ok
=> [ 1, 99 ]
=> 1
loaded ("second_answer" "ordinary_color")
reset all loaded native state
=> 5
=> "kept native text"
=> ("kept native list" 42)
=> 0
=> 9
EOF
sed 's/ *$//' "$tmp/out" >"$tmp/normalized"
cmp "$tmp/expected" "$tmp/normalized"
test ! -s "$tmp/err"

cat >"$tmp/broken.x" <<'EOF'
meta int broken(void) { return ;
EOF
cat >"$tmp/unlinked.x" <<'EOF'
int absent_native_body(int);
meta int unlinked(int n) { return absent_native_body(n); }
EOF
cp "$tmp/native.x" "$tmp/conflict.x"
printf '%s\n' ":load \"$tmp/native.x\"" 'loaded_answer(1);' \
  ":load \"$tmp/second.x\"" 'ordinary_color;' 'LOAD_RED;' \
  'loaded_answer(1);' \
  ':load no-quotes' ":load \"$tmp/missing.x\"" \
  ":load \"$tmp/broken.x\"" ":load \"$tmp/unlinked.x\"" \
  ":load \"$tmp/conflict.x\"" 'loaded_calls();' \
  'Array cycle = [];' 'cycle.push(cycle);' 'loaded_append(cycle);' \
  'loaded_calls();' 'loaded_exit();' 'loaded_calls();' '1+2;' \
  >"$tmp/input"
if builds/0/x2c repl <"$tmp/input" >"$tmp/out" 2>"$tmp/err"; then
  echo "failed loads and calls unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'usage: :load' "$tmp/err"
grep -q 'cannot read input file' "$tmp/err"
grep -q 'absent_native_body' "$tmp/err"
grep -q 'loaded_text' "$tmp/err"
grep -q '^=> 3$' "$tmp/out"
grep -q 'unresolved identifier: LOAD_RED' "$tmp/err"
grep -q 'arguments must be independent data values' "$tmp/err"
grep -q 'the body exited with status 9' "$tmp/err"
test "$(grep -c '^=> 1$' "$tmp/out")" -eq 2
tail -n 2 "$tmp/out" >"$tmp/recovery"
printf '=> 0\n=> 3\n' >"$tmp/recovery-expected"
cmp "$tmp/recovery-expected" "$tmp/recovery"

# A failed load can be fixed without restarting. An incompatible replacement
# cannot change earlier code, even before its first call or after a restart.
python3 - "$tmp" <<'PY'
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
source = root / "edited.x"
source.write_text("static int old_name(void) { return 1; }\n")
repl = subprocess.Popen(
    ["builds/0/x2c", "repl"], text=True,
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
repl.stdin.write(f':load "{source}"\n')
repl.stdin.flush()
assert "no public functions or supported globals" in repl.stderr.readline()
def version(number, parameter="void"):
    source.write_text(
        "#include <stdlib.h>\n"
        f"int fresh_name({parameter}) {{ return {number}; }}\n"
        "void end_helper(void) { exit(8); }\n")
version(41)
repl.stdin.write(f':load "{source}"\nunknown_sync;\n')
repl.stdin.flush()
line = repl.stderr.readline()
assert "unresolved identifier: unknown_sync" in line, line
version(42, "int n")
out, err = repl.communicate(
    f':load "{source}"\nfresh_name();\nend_helper();\nfresh_name();\n',
    timeout=60)
assert repl.returncode == 1, (out, err)
assert 'loaded ("fresh_name" "end_helper")' in out, (out, err)
assert out.count("=> 41\n") == 2 and "=> 42" not in out, (out, err)
assert "function type changed: fresh_name" in err, err
assert "the body exited with status 8" in err, err
PY

python3 commands/repl/tests/reload.py "$tmp"

# Every retained executable directory belongs to a closed session.
set -- "$tmp"/x2c-*
test ! -e "$1"
echo "REPL source load checks passed"
