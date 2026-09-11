#!/usr/bin/env bash
set -euo pipefail

# Regression probes for the raw symbol collection cache (src/collect.x):
# warm replay -- in-process or via etc/header-symbols.xlisp -- must be
# byte-identical to a cold walk, stale artifacts must be rejected, and
# unreadable includes must fail loudly.  Each case pins a bug found and
# fixed in the 2026-07 milestone review.

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/header-cache"
X2C=${X2C:-"$ROOT/builds/0/x2c"}

rm -rf "$BUILD"
mkdir -p "$BUILD"

fail() {
  echo "header cache probe failure: $1" >&2
  exit 1
}

# Scratch headers: hdr.x declares Foo then re-declares it via bar.x, so
# the winning definition pins merge order; anon.x consumes shallow-parse
# gensyms through anonymous aggregates.
mkdir -p "$BUILD/src"
cat >"$BUILD/src/bar.x" <<'EOF'
typedef List Foo;
EOF
cat >"$BUILD/src/hdr.x" <<'EOF'
typedef String Foo;
typedef List CacheSelfBase;
typedef CacheSelfBase CacheSelfLeaf;
typedef struct CacheDelegatePart { int value; } CacheDelegatePart;
typedef struct CacheDelegateOwner {
  delegate CacheDelegatePart part;
} CacheDelegateOwner;
Self CacheSelfBase.rest(Self value);
int CacheDelegatePart.read(CacheDelegatePart value);
#include "bar.x"
EOF
cat >"$BUILD/src/anon.x" <<'EOF'
typedef struct { int first; } AnonFirst;
typedef struct { int second; } AnonSecond;
EOF
cat >"$BUILD/src/unit.x" <<'EOF'
#include "hdr.x"
#include "anon.x"
int cache_external(int value);
int cache_call_external(int value) { return cache_external(value); }
macro Statement $cache_add(Expr $target, Expr $amount)
  using $temporary => {
  int $temporary = $amount;
  $target += $temporary;
}
int probe_use(Foo x, AnonFirst a) {
  int result = x.len() + a.first;
  $cache_add(result, 0);
  return result;
}
String CacheSelfLeaf.only(CacheSelfLeaf value) {
  return value.car().str();
}
int CacheDelegatePart.read(CacheDelegatePart value) {
  return value.value;
}
int probe_delegate(CacheDelegateOwner value) {
  return value.read();
}
String probe_self(CacheSelfLeaf value) {
  return value.rest().only();
}
EOF
cp "$BUILD/src/unit.x" "$BUILD/src/twin.x"

# Cases 1 and 2: merge order and gensym accounting.  A duplicated
# symbol and a gensym-consuming header must translate identically
# whether the walk is cold (batch-first, solo) or warm in-process
# (batch-second).
mkdir -p "$BUILD/batch" "$BUILD/solo"
"$X2C" translate --out-dir "$BUILD/batch" "$BUILD/src/twin.x" "$BUILD/src/unit.x"
"$X2C" translate --out-dir "$BUILD/solo" "$BUILD/src/unit.x"
"$X2C" translate --out-dir "$BUILD/solo" "$BUILD/src/twin.x"
cmp -s "$BUILD/batch/unit.c" "$BUILD/solo/unit.c" ||
  fail "warm in-process replay diverged from cold compile"
cmp -s "$BUILD/batch/twin.c" "$BUILD/solo/twin.c" ||
  fail "batch-first translation diverged from cold compile"
grep -q "List_len" "$BUILD/solo/unit.c" ||
  fail "cold walk resolved Foo to the wrong declaration"
grep -q '^int cache_external(int value);' "$BUILD/solo/unit.h" ||
  fail "public function declaration is missing from the generated header"
if grep -q '^int cache_external(' "$BUILD/solo/unit.c"; then
  fail "source repeats a function declaration supplied by its own header"
fi

# Translating an owner replaces its artifact entry with collected source.
# Its generated protocol callables must survive that replacement for later
# consumers, just as they do when loaded directly from the artifact.
cat >"$BUILD/src/array-consumer.x" <<'EOF'
#include "array.x"
void release(Array items) { items.free(); }
size_t count(Array items) { return items.len(); }
EOF
mkdir -p "$BUILD/owner-batch" "$BUILD/owner-parallel"
"$X2C" translate --out-dir "$BUILD/solo" "$BUILD/src/array-consumer.x"
"$X2C" translate --out-dir "$BUILD/owner-batch" \
  "$ROOT/lib/array.x" "$BUILD/src/array-consumer.x"
"$X2C" translate -j 2 --out-dir "$BUILD/owner-parallel" \
  "$ROOT/lib/array.x" "$BUILD/src/array-consumer.x"
for extension in c h; do
  for mode in owner-batch owner-parallel; do
    cmp -s "$BUILD/solo/array-consumer.$extension" \
      "$BUILD/$mode/array-consumer.$extension" ||
      fail "generated callable declarations changed under $mode"
  done
done

# Fake repo root: artifact paths are root-relative, so the probe gets
# its own root with the real compiler and snapshot copied in.  Root
# discovery climbs from the binary looking for src+include+lib.
FAKE="$BUILD/fake-root"
mkdir -p "$FAKE/src" "$FAKE/include" "$FAKE/lib" "$FAKE/etc" \
  "$FAKE/builds/0"
cp "$X2C" "$FAKE/builds/0/x2c"
cp "$ROOT/etc/symbols.xlisp" "$FAKE/etc/symbols.xlisp"
cp "$BUILD/src/bar.x" "$BUILD/src/hdr.x" "$BUILD/src/anon.x" \
  "$BUILD/src/unit.x" "$FAKE/src/"

# Case 3: artifact replay and staleness.  A warm run must reproduce the
# cold bytes; a tampered artifact must change the outcome (proving
# replay is live) until a snapshot edit invalidates the artifact
# wholesale via the banner content hash; a v1 banner is ignored.
mkdir -p "$FAKE/cold" "$FAKE/warm" "$FAKE/tampered" "$FAKE/rejected" \
  "$FAKE/v1"
(cd "$FAKE" && ./builds/0/x2c translate --dump-header-symbols \
  src/unit.x >etc/header-symbols.xlisp)
(cd "$FAKE" && ./builds/0/x2c translate --out-dir cold src/unit.x)
grep -q '"src/hdr.x"' "$FAKE/etc/header-symbols.xlisp" ||
  fail "artifact is missing the scratch header entry"
grep -q '(self "CacheSelfBase_rest")' \
  "$FAKE/etc/header-symbols.xlisp" ||
  fail "artifact is missing receiver-relative method metadata"
grep -q 'struct "CacheDelegateOwner" delegate "part"' \
  "$FAKE/etc/header-symbols.xlisp" ||
  fail "artifact is missing delegate field metadata"
(cd "$FAKE" && ./builds/0/x2c translate --out-dir warm src/unit.x)
cmp -s "$FAKE/cold/unit.c" "$FAKE/warm/unit.c" ||
  fail "artifact replay diverged from cold compile"
grep -q "_x2c_macro_" "$FAKE/cold/unit.c" ||
  fail "macro name stability probe emitted no generated name"
grep -q "CacheSelfLeaf_only(CacheSelfBase_rest(value))" \
  "$FAKE/cold/unit.c" ||
  fail "artifact replay lost the original receiver typedef"
grep -q "CacheDelegatePart_read(value.part)" \
  "$FAKE/cold/unit.c" ||
  fail "artifact replay lost delegate field lookup"

sed 's/"Foo"/"Fpo"/g' "$FAKE/etc/header-symbols.xlisp" \
  >"$FAKE/etc/header-symbols.tampered"
cp "$FAKE/etc/header-symbols.tampered" "$FAKE/etc/header-symbols.xlisp"
(cd "$FAKE" && ./builds/0/x2c translate --out-dir tampered src/unit.x) \
  >/dev/null 2>&1 || true
cmp -s "$FAKE/cold/unit.c" "$FAKE/tampered/unit.c" &&
  fail "tampered artifact rows did not reach replay (test is vacuous)"

printf '\n' >>"$FAKE/etc/symbols.xlisp"
(cd "$FAKE" && ./builds/0/x2c translate --out-dir rejected src/unit.x)
cmp -s "$FAKE/cold/unit.c" "$FAKE/rejected/unit.c" ||
  fail "snapshot edit did not invalidate the stale artifact"

cp "$ROOT/etc/symbols.xlisp" "$FAKE/etc/symbols.xlisp"
printf '(header-symbols 1 11 (\n))\n' >"$FAKE/etc/header-symbols.xlisp"
(cd "$FAKE" && ./builds/0/x2c translate --out-dir v1 src/unit.x) ||
  fail "v1 artifact banner was fatal instead of ignored"
cmp -s "$FAKE/cold/unit.c" "$FAKE/v1/unit.c" ||
  fail "v1 artifact was not ignored"

# Case 4: an entry with a dependency outside the repo root is skipped
# whole, never persisted with a silently narrowed dep list.
mkdir -p "$BUILD/outside" "$FAKE/extout"
cat >"$BUILD/outside/ext.x" <<'EOF'
typedef int ExtValue;
EOF
cat >"$FAKE/src/uses-ext.x" <<'EOF'
#include "ext.x"
int probe_ext(ExtValue v) { return v; }
EOF
(cd "$FAKE" && ./builds/0/x2c translate --dump-header-symbols \
  -I "$BUILD/outside" src/uses-ext.x >"$BUILD/ext-artifact.xlisp")
grep -q '"src/uses-ext.x"' "$BUILD/ext-artifact.xlisp" &&
  fail "entry with out-of-root dep was persisted"

# Case 5: unresolved targets contribute no cached symbols. An explicit
# host preprocess still rejects directory and unreadable include targets.
mkdir -p "$FAKE/src/dir-target.h" "$FAKE/dirout"
cat >"$FAKE/src/uses-dir.x" <<'EOF'
#include "dir-target.h"
int probe_dir(void) { return 0; }
EOF
if (cd "$FAKE" && ./builds/0/x2c translate --cpp-symbols --out-dir dirout src/uses-dir.x) \
    >/dev/null 2>"$BUILD/dir.err"; then
  fail "directory include target was silently accepted"
fi
grep -q "failed to run C preprocessor" "$BUILD/dir.err" ||
  fail "directory include target died without a diagnostic"

if [ "$(id -u)" != 0 ]; then
  mkdir -p "$FAKE/lockout"
  cat >"$FAKE/src/locked.h" <<'EOF'
typedef int LockedValue;
EOF
  cat >"$FAKE/src/uses-locked.x" <<'EOF'
#include "locked.h"
int probe_locked(LockedValue v) { return v; }
EOF
  chmod 000 "$FAKE/src/locked.h"
  status=0
  (cd "$FAKE" && ./builds/0/x2c translate --cpp-symbols --out-dir lockout src/uses-locked.x) \
    >/dev/null 2>"$BUILD/locked.err" || status=$?
  chmod 644 "$FAKE/src/locked.h"
  [ "$status" != 0 ] ||
    fail "unreadable include target was silently accepted"
  grep -q "failed to run C preprocessor" "$BUILD/locked.err" ||
    fail "unreadable include target died without a diagnostic"
fi

# Case 6: cross-batch gensym aliasing.  The header cache counter used
# to restart at the snapshot base for every unit, so a later unit
# could mint a gensym number a cached row already owned; two distinct
# anonymous aggregates then shared one key and whichever row replayed
# won, boxing a "long" field with a float tag.  h1.x and h2.x each
# introduce one anonymous aggregate; uc.x sees both and boxes a TypeA
# field into a Var.  Every batch ordering must produce byte-identical
# output, and it must actually exercise the i64 boxing path -- the
# pre-fix symptom was Var_new(3356265, ...) (a float-tagged box)
# showing up in some orderings instead of Var_box_long.
mkdir -p "$BUILD/gensym"
cat >"$BUILD/gensym/h1.x" <<'EOF'
typedef struct { long   v; } TypeA;
EOF
cat >"$BUILD/gensym/h2.x" <<'EOF'
typedef struct { double v; } TypeB;
EOF
cat >"$BUILD/gensym/ua.x" <<'EOF'
#include "h1.x"
int probe_use_a(TypeA a) { return (int) a.v; }
EOF
cat >"$BUILD/gensym/ub.x" <<'EOF'
#include "h2.x"
int probe_use_b(TypeB b) { return (int) b.v; }
EOF
cat >"$BUILD/gensym/uc.x" <<'EOF'
#include "h1.x"
#include "h2.x"
int probe_uc(TypeA a) {
  Var boxed = Var.box_long(a.v);
  return (int) boxed.pointer();
}
EOF

mkdir -p "$BUILD/gensym/o-uc" "$BUILD/gensym/o-ub-uc" \
  "$BUILD/gensym/o-ua-ub-uc" "$BUILD/gensym/o-uc-ua-ub" \
  "$BUILD/gensym/o-ua-uc"
(cd "$BUILD/gensym" && "$X2C" translate --out-dir o-uc uc.x)
(cd "$BUILD/gensym" && "$X2C" translate --out-dir o-ub-uc ub.x uc.x)
(cd "$BUILD/gensym" && "$X2C" translate --out-dir o-ua-ub-uc ua.x ub.x uc.x)
(cd "$BUILD/gensym" && "$X2C" translate --out-dir o-uc-ua-ub uc.x ua.x ub.x)
(cd "$BUILD/gensym" && "$X2C" translate --out-dir o-ua-uc ua.x uc.x)

grep -q "Var_box_long" "$BUILD/gensym/o-uc/uc.c" ||
  fail "gensym probe is vacuous: uc.c never boxes with Var_box_long"

for other in o-ub-uc o-ua-ub-uc o-uc-ua-ub o-ua-uc; do
  cmp -s "$BUILD/gensym/o-uc/uc.c" "$BUILD/gensym/$other/uc.c" ||
    fail "cross-batch gensym aliasing: uc.c diverged under $other"
done

# Case 7: no compiler-internal generated name may escape into emitted
# C.  Anonymous aggregates now emit the tagless form the source wrote
# instead of printing the gensym key as a C struct/union/enum tag.
# Generate a small anonymous-struct typedef into its own scratch dir
# so the assertion cannot pass vacuously by missing a stage directory.
mkdir -p "$BUILD/anon-escape"
cat >"$BUILD/anon-escape/anon.x" <<'EOF'
typedef struct { int first; } AnonEscape;
int probe_anon(AnonEscape a) { return a.first; }
EOF
mkdir -p "$BUILD/anon-escape/out"
(cd "$BUILD/anon-escape" && "$X2C" translate --out-dir out anon.x)
grep -q "AnonEscape" "$BUILD/anon-escape/out/anon.h" ||
  fail "anon-escape probe is vacuous: anon.h has no anonymous typedef"
grep -r "_x2c_gensym" "$BUILD/anon-escape/out" &&
  fail "generated name leaked into emitted C" || true

# Case 8: macro-generated names are reproducible across complete compiler
# runs, and an unrelated declaration inserted earlier in the same source
# does not renumber a later expansion.
macro_fixture="$ROOT/unittest/compiler-fixtures/macro-name-stability.x"
mkdir -p "$BUILD/macro-stability/repeat-a" \
  "$BUILD/macro-stability/repeat-b"
"$X2C" translate --out-dir "$BUILD/macro-stability/repeat-a" "$macro_fixture"
"$X2C" translate --out-dir "$BUILD/macro-stability/repeat-b" "$macro_fixture"
cmp -s "$BUILD/macro-stability/repeat-a/macro-name-stability.c" \
  "$BUILD/macro-stability/repeat-b/macro-name-stability.c" ||
  fail "macro-generated names changed across complete compiler runs"

cp "$macro_fixture" "$BUILD/macro-stability/edit.x"
mkdir -p "$BUILD/macro-stability/before" \
  "$BUILD/macro-stability/after"
"$X2C" translate --out-dir "$BUILD/macro-stability/before" \
  "$BUILD/macro-stability/edit.x"
awk 'NR == 2 { print "static int unrelated_name_edit;" } { print }' \
  "$BUILD/macro-stability/edit.x" \
  >"$BUILD/macro-stability/edit.tmp"
mv "$BUILD/macro-stability/edit.tmp" \
  "$BUILD/macro-stability/edit.x"
"$X2C" translate --out-dir "$BUILD/macro-stability/after" \
  "$BUILD/macro-stability/edit.x"
grep -o '_x2c_macro_[[:alnum:]_]*' \
  "$BUILD/macro-stability/before/edit.c" |
  LC_ALL=C sort -u >"$BUILD/macro-stability/before.names"
grep -o '_x2c_macro_[[:alnum:]_]*' \
  "$BUILD/macro-stability/after/edit.c" |
  LC_ALL=C sort -u >"$BUILD/macro-stability/after.names"
test -s "$BUILD/macro-stability/before.names" ||
  fail "macro edit-stability probe emitted no generated name"
cmp -s "$BUILD/macro-stability/before.names" \
  "$BUILD/macro-stability/after.names" ||
  fail "unrelated earlier edit renumbered a later macro name"

# Case 9: the macro and Lisp files a header reads are prerequisites of every
# unit that includes it, not only of the first unit to parse it.  A batch
# replays the second unit's copy of the header out of the cache and must
# include the header's own imports in the depfile.
mkdir -p "$BUILD/imports/src" "$BUILD/imports/out"
cat >"$BUILD/imports/src/probe.xmacro" <<'EOF'
$(def probe.step 3)
EOF
cat >"$BUILD/imports/src/hdr.x" <<'EOF'
$(import "probe.xmacro")
int probe_step(int n);
EOF
cat >"$BUILD/imports/src/first.x" <<'EOF'
#include "hdr.x"
int probe_step(int n) { return n + 1; }
EOF
cat >"$BUILD/imports/src/second.x" <<'EOF'
#include "hdr.x"
int probe_twice(int n) { return probe_step(n) + 2; }
EOF
(cd "$BUILD/imports" && "$X2C" translate --out-dir out src/first.x src/second.x)
grep -q "probe.xmacro" "$BUILD/imports/out/first.d" ||
  fail "imports probe is vacuous: even a cold walk omits the macro file"
grep -q "probe.xmacro" "$BUILD/imports/out/second.d" ||
  fail "a replayed header's macro import is missing from the depfile"

# A package's own compile-time imports belong to every importing unit. The
# package entry is replayed from its collection cache when the consumer's
# import is resolved, so both dependencies must survive that replay.
mkdir -p "$BUILD/package-import/packages/depcache/src" \
  "$BUILD/package-import/src" "$BUILD/package-import/out"
cat >"$BUILD/package-import/packages/depcache/src/helper.xmacro" <<'EOF'
macro Expression $depcache.answer() => (7)
EOF
cat >"$BUILD/package-import/packages/depcache/src/helper.xlisp" <<'EOF'
(def depcache-helper 1)
EOF
cat >"$BUILD/package-import/packages/depcache/src/depcache.x" <<'EOF'
$(import "helper.xmacro")
$(import "helper.xlisp")
typedef int Value;
class CachedValue { int value; };
#pragma private
class HiddenValue { int value; };
EOF
cat >"$BUILD/package-import/src/consumer.x" <<'EOF'
import "depcache" as dep;
int package_dependency(dep.Value value) { return value; }
int package_class(int value) {
  dep.CachedValue original = dep.CachedValue.new(value);
  Var boxed = original;
  return dep.Var_cachedvalue(boxed).value;
}
EOF
(cd "$BUILD/package-import" && "$X2C" translate \
  --package-dir packages --out-dir out src/consumer.x \
  packages/depcache/src/depcache.x)
grep -q "helper.xmacro" "$BUILD/package-import/out/consumer.d" ||
  fail "a package's macro import is missing from the consumer depfile"
grep -q "helper.xlisp" "$BUILD/package-import/out/consumer.d" ||
  fail "a package's Lisp import is missing from the consumer depfile"
grep -q 'depcache__Var_cachedvalue' \
  "$BUILD/package-import/out/depcache.h" ||
  fail "package class lost its canonical reverse converter"
! grep -q 'HiddenValue' "$BUILD/package-import/out/depcache.h" ||
  fail "private package class escaped through generated defaults"

# Case 10: aliases belong to one .x file. An included file may use its own
# aliases to contribute symbols, the including file keeps its aliases across
# the include, and neither file receives the other's aliases. Warm cache
# order must not change the generated result.
mkdir -p "$BUILD/keyword/src" "$BUILD/keyword/alias-first" \
  "$BUILD/keyword/main-first"
cat >"$BUILD/keyword/src/private-keywords.xmacro" <<'EOF'
macro Decorator $cache.identity(Function $target) => {
  $(x2c.function.body $target)...
}
macro Decorator $cache.outer(Function $target) => {
  $(x2c.function.body $target)...
}
keyword identity $cache.identity;
keyword outer $cache.outer;
EOF
cat >"$BUILD/keyword/src/child-keywords.xmacro" <<'EOF'
macro Expression $cache.child(Expr $value) => (99)
keyword child $cache.child;
EOF
cat >"$BUILD/keyword/src/nested.x" <<'EOF'
static int child(int value) { return value; }
EOF
cat >"$BUILD/keyword/src/alias.x" <<'EOF'
#include "x2c.x"
$(import "private-keywords.xmacro")
$(import "child-keywords.xmacro")
identity List cached_values(void) { return %[]; }
#include "nested.x"
static int child_local(void) { return child(1); }
EOF
cat >"$BUILD/keyword/src/main.x" <<'EOF'
#include "x2c.x"
$(import "private-keywords.xmacro")
#include "alias.x"
outer int cached_keyword_probe(void) {
  return cached_values().len() + child(4);
}
EOF
for order in alias-first main-first; do
  if [ "$order" = alias-first ]; then
    inputs=(src/alias.x src/main.x)
  else
    inputs=(src/main.x src/alias.x)
  fi
  (cd "$BUILD/keyword" && "$X2C" translate --out-dir "$order" \
    "${inputs[@]}")
done
cmp -s "$BUILD/keyword/alias-first/main.c" \
  "$BUILD/keyword/main-first/main.c" ||
  fail "keyword alias collection changed with cache order"
grep -q "child(4)" "$BUILD/keyword/alias-first/main.c" ||
  fail "included keyword alias leaked into its caller"
grep -q "cached_keyword_probe" "$BUILD/keyword/alias-first/main.h" ||
  fail "outer keyword alias was lost across an include"
grep -q "return 99" "$BUILD/keyword/alias-first/alias.c" ||
  fail "imported keyword alias was lost across an include"
for output in alias-first/main.d main-first/main.d; do
  grep -q "private-keywords.xmacro" "$BUILD/keyword/$output" ||
    fail "included keyword pack is missing from $output"
  grep -q "child-keywords.xmacro" "$BUILD/keyword/$output" ||
    fail "included child keyword pack is missing from $output"
done

# Case 11: embedded text is a canonical dependency, including through nested
# macro imports. Text dependencies participate in persisted header validity,
# so an unchanged artifact replays and a changed payload forces collection.
mkdir -p "$BUILD/embed/out"
(cd "$ROOT" && "$X2C" translate --out-dir \
  "$BUILD/embed/out" unittest/compiler-fixtures/macro-embed-text.x)
embed_dep="$BUILD/embed/out/macro-embed-text.d"
grep -Fq "macro-embed-text-definition/embed.xmacro" "$embed_dep" ||
  fail "outer macro import is missing from the embed depfile"
grep -Fq "macro-embed-text-definition/helper.xmacro" "$embed_dep" ||
  fail "nested macro import is missing from the embed depfile"
grep -Fq "macro-embed-text-definition/macro-embed-text-data.txt" \
  "$embed_dep" || fail "definition-relative text is missing from the depfile"
grep -Fq "macro-embed-text-data.txt" "$embed_dep" ||
  fail "caller-relative text is missing from the depfile"

mkdir -p "$BUILD/embed-invalid/src" "$BUILD/embed-invalid/out"
cat >"$BUILD/embed-invalid/src/embed.xmacro" <<'EOF'
macro Expression $probe.embed(Literal $path) => (
  $(x2c.literal.string (x2c.embed.text $path))
)
EOF
printf 'plain text' >"$BUILD/embed-invalid/src/plain.txt"
printf 'bad\0text' >"$BUILD/embed-invalid/src/nul.txt"
dd if=/dev/null of="$BUILD/embed-invalid/src/huge.txt" \
  bs=1 seek=2147483647 2>/dev/null
cat >"$BUILD/embed-invalid/src/nul.x" <<'EOF'
$(import "embed.xmacro")
String value = $probe.embed("nul.txt");
EOF
cat >"$BUILD/embed-invalid/src/huge.x" <<'EOF'
$(import "embed.xmacro")
String value = $probe.embed("huge.txt");
EOF
if "$X2C" translate --out-dir "$BUILD/embed-invalid/out" \
    "$BUILD/embed-invalid/src/nul.x" \
    >"$BUILD/embed-invalid/nul.stdout" \
    2>"$BUILD/embed-invalid/nul.stderr"; then
  fail "embedded NUL text was accepted"
fi
grep -Fq "embedded text contains an embedded NUL" \
  "$BUILD/embed-invalid/nul.stderr" ||
  fail "embedded NUL text died without its diagnostic"
if "$X2C" translate --out-dir "$BUILD/embed-invalid/out" \
    "$BUILD/embed-invalid/src/huge.x" \
    >"$BUILD/embed-invalid/huge.stdout" \
    2>"$BUILD/embed-invalid/huge.stderr"; then
  fail "oversized embedded text was accepted"
fi
grep -Fq "embedded text exceeds the String size limit" \
  "$BUILD/embed-invalid/huge.stderr" ||
  fail "oversized embedded text died without its diagnostic"
cat >"$BUILD/embed-invalid/src/absolute.x" <<EOF
\$(import "embed.xmacro")
String value = \$probe.embed("$BUILD/embed-invalid/src/plain.txt");
EOF
"$X2C" translate --out-dir "$BUILD/embed-invalid/out" \
  "$BUILD/embed-invalid/src/absolute.x"
plain_path=$(cd "$BUILD/embed-invalid/src" && pwd)/plain.txt
plain_count=$(head -n 1 "$BUILD/embed-invalid/out/absolute.d" |
  grep -oF "$plain_path" | wc -l | tr -d ' ')
[ "$plain_count" = 1 ] ||
  fail "canonical embedded dependency was not recorded exactly once"

embed_root="$BUILD/embed-cache-root"
mkdir -p "$embed_root/src" "$embed_root/include" "$embed_root/lib" \
  "$embed_root/etc" "$embed_root/builds/0" "$embed_root/cold" \
  "$embed_root/warm"
cp "$X2C" "$embed_root/builds/0/x2c"
cp "$ROOT/etc/symbols.xlisp" "$ROOT/etc/init.xlisp" \
  "$ROOT/etc/compiler-sdk.xlisp" "$ROOT/etc/builtin-macros.xlisp" \
  "$embed_root/etc/"
cat >"$embed_root/src/embed.xmacro" <<'EOF'
macro Unit $cache.declare() => {
  int $(x2c.ident (x2c.embed.text "name.txt"))(void);
}
EOF
cat >"$embed_root/src/hdr.x" <<'EOF'
$(import "embed.xmacro")
$cache.declare();
EOF
printf 'cold_name' >"$embed_root/src/name.txt"
cat >"$embed_root/src/main.x" <<'EOF'
#include "hdr.x"
int use_name(void) { return cold_name(); }
EOF
(cd "$embed_root" && ./builds/0/x2c translate --dump-header-symbols \
  src/main.x >etc/header-symbols.xlisp)
grep -Fq '"src/name.txt"' "$embed_root/etc/header-symbols.xlisp" ||
  fail "header artifact omitted its embedded text row"
(cd "$embed_root" && ./builds/0/x2c translate --out-dir cold src/main.x)
grep -Fq "$embed_root/src/name.txt" "$embed_root/cold/main.d" ||
  fail "replayed header omitted embedded text from its depfile"
printf 'warm_name' >"$embed_root/src/name.txt"
cat >"$embed_root/src/main.x" <<'EOF'
#include "hdr.x"
int use_name(void) { return warm_name(); }
EOF
(cd "$embed_root" && ./builds/0/x2c translate --out-dir warm src/main.x)
grep -q "warm_name" "$embed_root/warm/main.c" ||
  fail "changed embedded text did not invalidate the header artifact"

# Declaration bundles retain one production across source segments and the
# full parse. Nested producers and body-only Lisp keep their captured values;
# late ordinary methods suppress only the matching default candidate.
declarations="$BUILD/declaration-bundles"
mkdir -p "$declarations/src"
cat >"$declarations/src/effects.xlisp" <<EOF2
(def read-file
  (bind "lisp_read_file" '((func (("String"))) "Var")))
(def write-file
  (bind "lisp_write_file" '((func (("String") ("String"))) "Var")))
(def projection-effect-path "$declarations/effects")
(write-file "$declarations/effects"
  (string-append (read-file "$declarations/effects") "i"))
(def projection-count 0)
(defun projection-name ()
  (begin
    (def projection-count (+ projection-count 1))
    (write-file "$declarations/effects"
      (string-append (read-file "$declarations/effects") "x"))
    (x2c.ident "projected_answer")))
(defun projection-field ()
  (begin
    (write-file "$declarations/effects"
      (string-append (read-file "$declarations/effects") "f"))
    (x2c.ident "value")))
EOF2
cat >"$declarations/src/producer.xmacro" <<'EOF2'
$(import "effects.xlisp")
$(write-file projection-effect-path
  (string-append (read-file projection-effect-path) "m"))
macro Field $projection.field() => { int $(projection-field); }
macro Declaration $projection.inner(Expr $value) => {
  int $(projection-name)(void) { return $(car (list $value)); }
  $(quote (
    (default (function (int) (bind ("selected_answer") ((fnmod (params))))
      (block (return () (expr (int) (literal (int) "7"))))))
    (default (function (int) (bind ("default_answer") ((fnmod (params))))
      (block (return () (expr (int) (literal (int) "9"))))))
  ))...
}
macro Declaration $projection.outer(Expr $value) => {
  $projection.inner($value);
}
EOF2
cat >"$declarations/src/provider.x" <<'EOF2'
$(import "producer.xmacro")
$(def projection-local-count 0)
$(defun projection-local-name ()
  (begin
    (def projection-local-count (+ projection-local-count 1))
    (x2c.ident "local_answer")))
$(defun projection-late ()
  '(function (int) (bind ("default_answer") ((fnmod (params))))
    (block (return () (expr (int) (literal (int) "29"))))))
$projection.outer(42);
class ProjectedField { $projection.field(); };
int field_value(ProjectedField value) { return value.value; }
#include "boundary.x"
macro Declaration $projection.local() => {
  int $(projection-local-name)(void) { return 23; }
}
$projection.local();
macro Declaration $projection.late() => {
  $(quote ((declaration-recipe projection-late ())))...
}
$projection.late();
int selected_answer(void) { return 11; }
int imported_count(void) { return $(x2c.literal.int projection-count); }
int local_count(void) { return $(x2c.literal.int projection-local-count); }
EOF2
: >"$declarations/src/boundary.x"
cat >"$declarations/src/consumer.x" <<'EOF2'
#include "provider.x"
int consume(void) {
  return projected_answer() + selected_answer() + default_answer();
}
EOF2
for mode in default live cpp; do
  mkdir -p "$declarations/$mode"
  : >"$declarations/effects"
  options=()
  case "$mode" in
    live) options+=(--live-symbols) ;;
    cpp) options+=(--cpp-symbols) ;;
  esac
  "$X2C" translate "${options[@]}" --out-dir "$declarations/$mode" \
    "$declarations/src/provider.x" "$declarations/src/consumer.x"
  [ "$(cat "$declarations/effects")" = imxf ] ||
    fail "declaration import, producer, or field ran twice in $mode mode"
  for file in provider.c provider.h consumer.c consumer.h; do
    cmp -s "$declarations/default/$file" "$declarations/$mode/$file" ||
      fail "declaration projection differs in $mode mode: $file"
  done
done
grep -q 'return 11;' "$declarations/default/provider.c" ||
  fail "late ordinary method did not replace its default"
! grep -q 'return 7;' "$declarations/default/provider.c" ||
  fail "discarded declaration default was emitted"
grep -q 'return 29;' "$declarations/default/provider.c" ||
  fail "later declaration recipe did not replace its default"
! grep -q 'return 9;' "$declarations/default/provider.c" ||
  fail "default survived a later ordinary declaration recipe"
grep -q 'return 42;' "$declarations/default/provider.c" ||
  fail "deferred body lost its macro arguments"
for counter in imported_count local_count; do
  grep -A2 "^int $counter(void)" "$declarations/default/provider.c" |
    grep -q 'return 1;' ||
    fail "declaration replay reset or repeated compile-time source effects"
done

# Private default methods retain internal linkage, and arbitrary recipe data
# round-trips even when its List head matches a serialization marker.
cat >"$declarations/src/private.x" <<'EOF2'
$(defun projection-data (data)
  `(return () ,(x2c.literal.int
    (if (equal? data '(declaration-void)) 17 19))))
macro Declaration $projection.data() => {
  $(quote ((function (int) (bind ("data_answer") ((fnmod (params))))
    (block (syntax-recipe projection-data ((declaration-void)))))))...
}
$projection.data();
#pragma private
class Hidden { int value; };
class HiddenAlias Hidden;
int private_answer(void) { return HiddenAlias.new(5).value; }
EOF2
"$X2C" translate --out-dir "$declarations/default" \
  "$declarations/src/private.x"
! grep -q 'Hidden' "$declarations/default/private.h" ||
  fail "private declaration defaults leaked their type into the header"
grep -q 'static Hidden Hidden_new' "$declarations/default/private.c" ||
  fail "private declaration default lost internal linkage"
grep -q 'static HiddenAlias HiddenAlias_new' \
  "$declarations/default/private.c" ||
  fail "private forwarding default lost internal linkage"
grep -q 'return 17;' "$declarations/default/private.c" ||
  fail "retained recipe data collided with a serialization marker"

# Persisted projection retains the mutable signature overlay in the header
# cache owner. A warm consumer must see default functions without rerunning
# the producer; changing its macro dependency invalidates that surface.
declaration_root="$BUILD/declaration-artifact"
mkdir -p "$declaration_root/src" "$declaration_root/etc" \
  "$declaration_root/include" "$declaration_root/lib" \
  "$declaration_root/builds/0" "$declaration_root/out"
cp "$X2C" "$declaration_root/builds/0/x2c"
cp "$ROOT/etc/symbols.xlisp" "$ROOT/etc/init.xlisp" \
  "$ROOT/etc/compiler-sdk.xlisp" "$ROOT/etc/builtin-macros.xlisp" \
  "$declaration_root/etc/"
cat >"$declaration_root/src/producer.xmacro" <<'EOF2'
$(def read-file (bind "lisp_read_file" '((func (("String"))) "Var")))
$(def write-file
  (bind "lisp_write_file" '((func (("String") ("String"))) "Var")))
$(write-file "effects" (string-append (read-file "effects") "x"))
macro Declaration $projection.persist() => {
  $(quote (
    (default (function (int) (bind ("persisted_answer") ((fnmod (params))))
      (block (return () (expr (int) (literal (int) "13"))))))
  ))...
}
EOF2
cat >"$declaration_root/src/provider.x" <<'EOF2'
$(import "producer.xmacro")
$projection.persist();
EOF2
cat >"$declaration_root/src/consumer.x" <<'EOF2'
#include "provider.x"
int consume(void) { return persisted_answer(); }
EOF2
: >"$declaration_root/effects"
(cd "$declaration_root" && ./builds/0/x2c translate --dump-header-symbols \
  src/consumer.x >etc/header-symbols.xlisp)
[ "$(cat "$declaration_root/effects")" = x ] ||
  fail "persisted declaration producer did not run exactly once"
: >"$declaration_root/effects"
(cd "$declaration_root" && ./builds/0/x2c translate --out-dir out src/consumer.x)
[ ! -s "$declaration_root/effects" ] ||
  fail "warm declaration artifact reran its producer"
sed 's/persisted_answer/changed_answer/g' \
  "$declaration_root/src/producer.xmacro" >"$declaration_root/src/changed"
mv "$declaration_root/src/changed" "$declaration_root/src/producer.xmacro"
sed 's/persisted_answer/changed_answer/g' \
  "$declaration_root/src/consumer.x" >"$declaration_root/src/changed"
mv "$declaration_root/src/changed" "$declaration_root/src/consumer.x"
(cd "$declaration_root" && ./builds/0/x2c translate --out-dir out src/consumer.x)
[ "$(cat "$declaration_root/effects")" = x ] ||
  fail "changed declaration macro did not invalidate its artifact"
grep -q 'changed_answer' "$declaration_root/out/consumer.c" ||
  fail "consumer retained a stale declaration signature"

echo "header cache probes passed"
