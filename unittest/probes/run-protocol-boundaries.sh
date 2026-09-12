#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUILD="$ROOT/unittest/build/protocol-probes"
SOURCE="$ROOT/unittest/probes/protocol"
FIXTURES="$ROOT/unittest/compiler-fixtures"
X2C=${X2C:-"$ROOT/builds/0/x2c"}
CC=${CC:-cc}

rm -rf "$BUILD"
mkdir -p "$BUILD/tag-scope" "$BUILD/header-batch" "$BUILD/header-solo" \
  "$BUILD/converter" "$BUILD/wrong-case" "$BUILD/protocol-batch" \
  "$BUILD/protocol-solo" "$BUILD/protocol-units" \
  "$BUILD/protocol-conflict-cold" "$BUILD/protocol-conflict-warm" \
  "$BUILD/protocol-owner" "$BUILD/protocol-basedefault" \
  "$BUILD/protocol-basedefault-solo" \
  "$BUILD/protocol-static" \
  "$BUILD/protocol-inherited/snapshot" \
  "$BUILD/protocol-generated-owner" \
  "$BUILD/protocol-generated-repeat" \
  "$BUILD/protocol-generated-import" \
  "$BUILD/var-shared-representation" \
  "$BUILD/var-explicit-tag-collision" \
  "$BUILD/var-explicit-tag-builtin"

fail() {
  echo "protocol boundary probe failure: $1" >&2
  exit 1
}

if "$X2C" translate --out-dir "$BUILD/tag-scope" \
    "$SOURCE/tag-scope-a.x" "$SOURCE/tag-scope-b.x" \
    >"$BUILD/tag-scope/stdout" 2>"$BUILD/tag-scope/stderr"; then
  fail "a source-declared Var tag leaked into the next translation unit"
fi
grep -q 'cannot convert ("Vec") to Var without loss' \
  "$BUILD/tag-scope/stderr" ||
  fail "tag-scope rejection did not report the missing conversion"

"$X2C" translate --out-dir "$BUILD/header-batch" \
  "$SOURCE/header-primer.x" "$SOURCE/header-unit.x"
"$X2C" translate --out-dir "$BUILD/header-solo" "$SOURCE/header-unit.x"
cmp -s "$BUILD/header-batch/header-unit.c" \
  "$BUILD/header-solo/header-unit.c" ||
  fail "warm header replay diverged from cold custom boxing"
grep -q 'Vec_var' "$BUILD/header-solo/header-unit.c" ||
  fail "source-declared boxing bypassed its exact converter"

"$X2C" translate --out-dir "$BUILD/converter" "$SOURCE/converter-count.x"
"$CC" -iquote "$ROOT/include" "$BUILD/converter/converter-count.c" \
  -L"$ROOT/builds/0" -lx2c -lm \
  -o "$BUILD/converter/converter-count"
"$BUILD/converter/converter-count" >"$BUILD/converter/stdout"
grep -qx '1 1' "$BUILD/converter/stdout" ||
  fail "ordinary custom boxing did not call P.var exactly once"

"$X2C" translate --out-dir "$BUILD/wrong-case" "$SOURCE/wrong-case.x"
"$CC" -iquote "$ROOT/include" "$BUILD/wrong-case/wrong-case.c" \
  -L"$ROOT/builds/0" -lx2c -lm -o "$BUILD/wrong-case/wrong-case"
if ( "$BUILD/wrong-case/wrong-case" \
      >"$BUILD/wrong-case/stdout" 2>"$BUILD/wrong-case/stderr"
    child_status=$?
    exit "$child_status"
  ) 2>/dev/null; then
  fail "mixed-case registration silently accepted lowercase custom boxing"
fi
grep -q 'bad-target' "$BUILD/wrong-case/stderr" ||
  fail "mixed-case registration failed without rejecting the custom tag"

"$X2C" translate --out-dir "$BUILD/protocol-batch" \
  "$SOURCE/protocol-cache-primer.x" "$SOURCE/protocol-cache-unit.x"
"$X2C" translate --out-dir "$BUILD/protocol-solo" "$SOURCE/protocol-cache-unit.x"
cmp -s "$BUILD/protocol-batch/protocol-cache-unit.c" \
  "$BUILD/protocol-solo/protocol-cache-unit.c" ||
  fail "warm protocol replay diverged from cold collection"

"$X2C" translate --out-dir "$BUILD/protocol-units" \
  "$SOURCE/protocol-unit-a.x" "$SOURCE/protocol-unit-b.x"

if "$X2C" translate --out-dir "$BUILD/protocol-conflict-cold" \
    "$SOURCE/protocol-conflict-unit.x" \
    >"$BUILD/protocol-conflict-cold/stdout" \
    2>"$BUILD/protocol-conflict-cold/stderr"; then
  fail "cold conflicting protocol declarations were accepted"
fi
if "$X2C" translate --out-dir "$BUILD/protocol-conflict-warm" \
    "$SOURCE/protocol-conflict-primer-a.x" \
    "$SOURCE/protocol-conflict-unit.x" \
    >"$BUILD/protocol-conflict-warm/stdout" \
    2>"$BUILD/protocol-conflict-warm/stderr"; then
  fail "warm conflicting protocol declarations were accepted"
fi
grep -q 'conflicting protocol declarations' \
  "$BUILD/protocol-conflict-cold/stderr" ||
  fail "cold conflict did not report the protocol cause"
cmp -s "$BUILD/protocol-conflict-cold/stderr" \
  "$BUILD/protocol-conflict-warm/stderr" ||
  fail "warm protocol conflict diagnostic diverged from cold collection"

FAKE="$BUILD/fake-root"
mkdir -p "$FAKE/src" "$FAKE/include" "$FAKE/lib" "$FAKE/etc" \
  "$FAKE/builds/0" "$FAKE/artifact-out" "$FAKE/conflict-out"
cp "$X2C" "$FAKE/builds/0/x2c"
cp "$ROOT/etc/symbols.xlisp" "$FAKE/etc/symbols.xlisp"
cp "$SOURCE"/protocol-conflict-{a,b,primer-a,primer-b,unit}.x "$FAKE/src/"
(cd "$FAKE" && ./builds/0/x2c translate --dump-header-symbols \
  src/protocol-conflict-primer-a.x src/protocol-conflict-primer-b.x \
  >etc/header-symbols.xlisp)
grep -q 'source-node' "$FAKE/etc/header-symbols.xlisp" ||
  fail "header artifact omitted retained protocol nodes"
if (cd "$FAKE" && ./builds/0/x2c translate --out-dir conflict-out \
    src/protocol-conflict-unit.x) \
    >"$FAKE/conflict.stdout" 2>"$FAKE/conflict.stderr"; then
  fail "artifact-replayed conflicting protocols were accepted"
fi
grep -q 'conflicting protocol declarations' "$FAKE/conflict.stderr" ||
  fail "artifact conflict did not report the protocol cause"
grep -q 'protocol-conflict-a.x' "$FAKE/conflict.stderr" ||
  fail "artifact conflict did not name the first declaration"
grep -q 'protocol-conflict-b.x' "$FAKE/conflict.stderr" ||
  fail "artifact conflict did not name the second declaration"

"$X2C" translate --out-dir "$BUILD/protocol-owner" \
  "$SOURCE/protocol-owner.x" "$SOURCE/protocol-consumer.x"
grep -q '_x2c_proto_vec_str' "$BUILD/protocol-owner/protocol-owner.c" ||
  fail "forward-converter owner omitted its descriptor thunk"
grep -q 'x2c_register_descriptor' \
  "$BUILD/protocol-owner/protocol-owner.c" ||
  fail "forward-converter owner omitted descriptor registration"
if grep -q '_x2c_proto_vec_str\\|x2c_register_descriptor' \
    "$BUILD/protocol-owner/protocol-consumer.c"; then
  fail "protocol consumer claimed owner-local runtime artifacts"
fi
"$CC" -iquote "$ROOT/include" -iquote "$BUILD/protocol-owner" \
  "$BUILD/protocol-owner/protocol-owner.c" \
  "$BUILD/protocol-owner/protocol-consumer.c" \
  -L"$ROOT/builds/0" -lx2c -lm \
  -o "$BUILD/protocol-owner/protocol-owner"
"$BUILD/protocol-owner/protocol-owner" \
  >"$BUILD/protocol-owner/stdout"
grep -qx 'owned' "$BUILD/protocol-owner/stdout" ||
  fail "owner/consumer descriptor dispatch did not link and run"

# Base-default method lookup across an owner/consumer boundary. The owner
# emits the generated Feet_magnitude binding for the base-default member;
# the consumer must reach it through the conformance table, not a phantom
# binding, in two distinct function bodies (same-invocation + cache/
# snapshot replay). Both units compiled together, then the consumer alone
# (warm-replay path) must translate byte-identically for its own source.
"$X2C" translate --out-dir "$BUILD/protocol-basedefault" \
  "$SOURCE/protocol-basedefault-owner.x" \
  "$SOURCE/protocol-basedefault-consumer.x"
grep -Eq '^double Feet_magnitude\([^;]*\)[[:space:]]*\{' \
  "$BUILD/protocol-basedefault/protocol-basedefault-owner.c" ||
  fail "base-default owner omitted its generated member binding"
if grep -Eq '^double Feet_magnitude\([^;]*\)[[:space:]]*\{' \
    "$BUILD/protocol-basedefault/protocol-basedefault-consumer.c"; then
  fail "base-default consumer defined the generated binding instead of \
consulting the conformance table"
fi
grep -q 'Feet_magnitude(value)' \
  "$BUILD/protocol-basedefault/protocol-basedefault-consumer.c" ||
  fail "base-default consumer did not resolve the dot call to the \
generated binding"
"$CC" -iquote "$ROOT/include" -iquote "$BUILD/protocol-basedefault" \
  "$BUILD/protocol-basedefault/protocol-basedefault-owner.c" \
  "$BUILD/protocol-basedefault/protocol-basedefault-consumer.c" \
  -L"$ROOT/builds/0" -lx2c -lm \
  -o "$BUILD/protocol-basedefault/protocol-basedefault"
"$BUILD/protocol-basedefault/protocol-basedefault" \
  >"$BUILD/protocol-basedefault/stdout"
grep -qx '1.5 1.5 1.5 1.5' "$BUILD/protocol-basedefault/stdout" ||
  fail "base-default owner/consumer dot calls did not resolve and run"

# A plain adoption whose converter pair is private is usable only by its
# declaring translation unit. Its generated binding must have internal
# linkage in owner C, stay out of the owner header, and remain unavailable
# to an including consumer under both symbol transports.
"$X2C" translate --out-dir "$BUILD/protocol-static" \
  "$SOURCE/protocol-static-owner.x"
grep -q '^static inline double StaticFeet_magnitude(' \
  "$BUILD/protocol-static/protocol-static-owner.c" ||
  fail "inferred-local adoption omitted its internal generated binding"
grep -q 'StaticItems_iter(values,' \
  "$BUILD/protocol-static/protocol-static-owner.c" ||
  fail "owner did not inherit its local ancestor adoption"
if grep -q 'StaticFeet_magnitude' \
    "$BUILD/protocol-static/protocol-static-owner.h"; then
  fail "inferred-local adoption leaked its binding into the owner header"
fi
for mode in snapshot; do
  flags=()
  if "$X2C" translate "${flags[@]}" \
      --out-dir "$BUILD/protocol-static" \
      "$SOURCE/protocol-static-consumer.x" \
      >"$BUILD/protocol-static/$mode.stdout" \
      2>"$BUILD/protocol-static/$mode.stderr"; then
    fail "$mode consumer used a foreign inferred-local adoption"
  fi
  grep -q 'has no method magnitude' \
    "$BUILD/protocol-static/$mode.stderr" ||
    fail "$mode inferred-local rejection did not name the missing method"
done
for mode in snapshot; do
  flags=()
  if "$X2C" translate "${flags[@]}" \
      --out-dir "$BUILD/protocol-static" \
      "$SOURCE/protocol-static-inherited-consumer.x" \
      >"$BUILD/protocol-static/inherited-$mode.stdout" \
      2>"$BUILD/protocol-static/inherited-$mode.stderr"; then
    fail "$mode consumer inherited a foreign local ancestor adoption"
  fi
  grep -q 'is not iterable' \
    "$BUILD/protocol-static/inherited-$mode.stderr" ||
    fail "$mode inherited-local rejection did not name iteration"
done
# An unadopted descendant uses the nearest visible ancestor conformance.
# Its same-named method does not replace the ancestor's resolved choice;
# an exact child adoption does.
inherited="$FIXTURES/protocol-typedef-inherited-adoption.x"
for mode in snapshot; do
  flags=()
  out="$BUILD/protocol-inherited/$mode"
  "$X2C" translate "${flags[@]}" --out-dir "$out" "$inherited"
  "$CC" -iquote "$ROOT/include" \
    "$out/protocol-typedef-inherited-adoption.c" \
    -L"$ROOT/builds/0" -lx2c -lm -o "$out/program"
  "$out/program" >"$out/stdout"
  cmp -s "$FIXTURES/protocol-typedef-inherited-adoption.stdout" \
    "$out/stdout" ||
    fail "$mode inherited protocol behavior changed"
done
"$X2C" translate --dump-conformance "$inherited" \
  >"$BUILD/protocol-inherited/conformance"
grep -Fq '(conformance owned ("Iter") ("IterParent")' \
  "$BUILD/protocol-inherited/conformance" ||
  fail "inherited protocol probe omitted the ancestor adoption"
grep -Fq '(conformance owned ("Iter") ("IterOverride")' \
  "$BUILD/protocol-inherited/conformance" ||
  fail "inherited protocol probe omitted the exact child adoption"
if grep -Fq '(conformance owned ("Iter") ("IterInherited")' \
    "$BUILD/protocol-inherited/conformance"; then
  fail "inherited protocol use created a child conformance row"
fi
if grep -Fq '(conformance owned ("Iter") ("IterDelegateOwner")' \
    "$BUILD/protocol-inherited/conformance"; then
  fail "delegated protocol use created an outer conformance row"
fi

# Generated-member ownership must be independent of declaration order. Each
# precedence case emits exactly one Packet_truth definition and has the same
# runtime behavior; each same-kind collision is rejected and names both
# competing protocol owners.
for mode in snapshot; do
  flags=()
  for name in protocol-generated-owner-precedence \
      protocol-generated-owner-precedence-swapped; do
    out="$BUILD/protocol-generated-owner/$mode-$name"
    mkdir -p "$out"
    "$X2C" translate "${flags[@]}" --out-dir "$out" "$FIXTURES/$name.x"
    count=$(grep -c '^int Packet_truth(Packet a0){$' "$out/$name.c")
    [[ "$count" == 1 ]] ||
      fail "$mode $name emitted $count Packet_truth definitions"
    "$CC" -iquote "$ROOT/include" "$out/$name.c" \
      -L"$ROOT/builds/0" -lx2c -lm -o "$out/program"
    "$out/program" >"$out/stdout"
    cmp -s "$FIXTURES/$name.stdout" "$out/stdout" ||
      fail "$mode $name changed generated-owner behavior"
  done

  for name in protocol-generated-collision \
      protocol-generated-collision-swapped; do
    out="$BUILD/protocol-generated-owner/$mode-$name"
    mkdir -p "$out"
    if "$X2C" translate "${flags[@]}" --out-dir "$out" \
        "$FIXTURES/$name.x" \
        >"$out/stdout" 2>"$out/stderr"; then
      fail "$mode $name accepted competing generated owners"
    fi
    grep -q 'FirstTruth(Choice) and SecondTruth(Choice)' "$out/stderr" ||
      fail "$mode $name did not name both generated owners"
  done
done
# A protocol adoption emitted after its participant methods must classify
# against those completed methods. The same generated source nodes feed the
# conformance and symbol-snapshot inspection paths.
generated="$FIXTURES/macro-generated-protocol-adoption.x"
"$X2C" translate --dump-conformance "$generated" \
  >"$BUILD/generated-conformance"
grep -Fq '(conformance owned ("Var") ("MacroArrayInt")' \
  "$BUILD/generated-conformance" ||
  fail "generated adoption was absent from conformance output"
grep -Fq '(contains implemented MacroArrayInt_contains dot+punctuation)' \
  "$BUILD/generated-conformance" ||
  fail "generated adoption hid its native contains method"
grep -Fq '(getindex implemented MacroArrayInt_getindex dot+punctuation)' \
  "$BUILD/generated-conformance" ||
  fail "generated adoption hid its native getindex method"
"$X2C" translate --dump-symbol-snapshot "$generated" \
  >"$BUILD/generated-tag-snapshot"
grep -F '(adopt ("Var") ("MacroArrayInt")' \
  "$BUILD/generated-tag-snapshot" >"$BUILD/generated-tag-row-snapshot"
grep -Fq '(tag (expr ("Symbol") (literal ("Symbol") "<macarray>" macarray)))' \
  "$BUILD/generated-tag-snapshot" ||
  fail "generated adoption omitted its explicit tag"

# A Var participant inherits methods only from the representation named by an
# explicit `as` adoption. A plain Var adoption over the same typedef ancestry
# retains its own descriptor and must not acquire the ancestor's methods.
shared="$FIXTURES/var-shared-representation.x"
shared_dump="$BUILD/var-shared-representation/conformance"
"$X2C" translate --dump-conformance "$shared" >"$shared_dump"
"$X2C" translate --out-dir "$BUILD/var-shared-representation" "$shared"
row=$(grep -F '(conformance owned ("Var") ("Row")' "$shared_dump")
plain=$(grep -F '(conformance owned ("Var") ("PlainRow")' "$shared_dump")
cell=$(grep -F '(conformance owned ("Var") ("Cell")' "$shared_dump")
[[ "$row" == *'(repr implemented List_repr dot+punctuation)'* ]] ||
  fail "shared List representation did not supply Row.repr"
[[ "$row" == *'(equal implemented List_equal dot+punctuation)'* ]] ||
  fail "shared List representation did not supply Row.equal"
[[ "$plain" != *'implemented List_'* ]] ||
  fail "plain Var adoption inherited List methods"
[[ "$cell" != *'implemented List_'* ]] ||
  fail "void pointer representation inherited List methods"
if grep -Fq '(conformance owned ("Var") ("PlainRowChild")' \
    "$shared_dump"; then
  fail "Var descendant gained a conformance row"
fi
shared_c="$BUILD/var-shared-representation/var-shared-representation.c"
descriptor_count=$(grep -c '^static VarMethods ' "$shared_c")
[[ "$descriptor_count" == 1 ]] ||
  fail "Var descendant changed the descriptor count"
if grep -Fq 'plainrowchild' "$shared_c"; then
  fail "Var descendant gained a tag or registration"
fi

"$X2C" translate --dump-symbol-snapshot \
  "$FIXTURES/macro-source-parity.x" >"$BUILD/generated-snapshot"
grep -Fq '("GeneratedProtocol")' "$BUILD/generated-snapshot" ||
  fail "generated protocol was absent from the symbol snapshot"
grep -Fq '(adopt ("GeneratedProtocol") ("DirectValue")' \
  "$BUILD/generated-snapshot" ||
  fail "generated adoption was absent from the symbol snapshot"

# Definition-site locations repeat across invocations of one macro. Retained
# keys use the invocation site as a separate identity so both protocol rows
# survive without changing their diagnostic locations.
repeat="$FIXTURES/macro-generated-protocol-repeat.x"
repeat_build="$BUILD/protocol-generated-repeat"
"$X2C" translate --dump-conformance "$repeat" \
  >"$repeat_build/conformance-default"
for participant in RepeatOne RepeatTwo; do
  grep -Fq "(conformance owned (\"Var\") (\"$participant\")" \
    "$repeat_build/conformance-default" ||
    fail "generated conformance omitted $participant"
done

"$X2C" translate --dump-symbol-snapshot "$repeat" \
  >"$repeat_build/snapshot-first"
"$X2C" translate --dump-symbol-snapshot "$repeat" \
  >"$repeat_build/snapshot-second"
cmp -s "$repeat_build/snapshot-first" \
  "$repeat_build/snapshot-second" ||
  fail "repeated generated protocol snapshot is not deterministic"
for participant in RepeatOne RepeatTwo; do
  grep -Fq "(adopt (\"Var\") (\"$participant\")" \
    "$repeat_build/snapshot-first" ||
    fail "generated snapshot omitted $participant adoption"
done
for base in RepeatProtocolA RepeatProtocolB; do
  grep -Fq "(protocol (\"protocol-record\" (\"$base\")" \
    "$repeat_build/snapshot-first" ||
    fail "generated snapshot omitted $base declaration"
done

mkdir -p "$repeat_build/default"
"$X2C" translate --out-dir "$repeat_build/default" "$repeat"
grep -Eq 'RepeatOne_contains\(a,[[:space:]]+31\)' \
  "$repeat_build/default/macro-generated-protocol-repeat.c" ||
  fail "snapshot-mode typed method syntax omitted RepeatOne"
grep -Eq 'RepeatTwo_contains\(b,[[:space:]]+47\)' \
  "$repeat_build/default/macro-generated-protocol-repeat.c" ||
  fail "snapshot-mode typed method syntax omitted RepeatTwo"

# Import collection expands unit macros transactionally and transports their
# public declarations with the retained protocol rows. The consumer must
# resolve both generated signatures and adoptions without compiling the
# provider as a separate input.
import_build="$BUILD/protocol-generated-import"
"$X2C" translate --out-dir "$import_build" -I "$SOURCE" \
  "$SOURCE/macro-protocol-export-consumer.x"
for participant in ExportOne ExportTwo; do
  grep -Eq "${participant}_setindex\(" \
    "$import_build/macro-protocol-export-consumer.c" ||
    fail "imported generated adoption omitted $participant"
done
"$X2C" translate --dump-symbol-snapshot -I "$SOURCE" \
  "$SOURCE/macro-protocol-export-consumer.x" \
  >"$import_build/snapshot"
for participant in ExportOne ExportTwo; do
  grep -Fq "(adopt (\"Var\") (\"$participant\")" \
    "$import_build/snapshot" ||
    fail "imported snapshot omitted $participant"
done

# Two type names longer than a compact Symbol encode to one tag. The second
# descriptor registration must name both spellings and abort rather than
# overwrite the first type's methods. That happens during unit
# initialization, so the program never reaches main.
collision_build="$BUILD/var-tag-collision"
mkdir -p "$collision_build"
"$X2C" translate --out-dir "$collision_build" "$SOURCE/var-tag-collision.x"
"$CC" -iquote "$ROOT/builds/0/lib" -iquote "$collision_build" \
  "$collision_build/var-tag-collision.c" \
  -L"$ROOT/builds/0" -lx2c -lm -o "$collision_build/var-tag-collision"

set +e
( "$collision_build/var-tag-collision" \
    >"$collision_build/stdout" 2>"$collision_build/stderr"
  child_status=$?
  exit "$child_status"
) 2>/dev/null
collision_status=$?
set -e

collision_message="Var descriptor: tag <tagcollisi> names both"
collision_message="$collision_message tagcollisionone and tagcollisiontwo"

test "$collision_status" -ne 0 || fail "colliding Var tags did not abort"
test ! -s "$collision_build/stdout" || fail "colliding Var tags reached main"
grep -Fq "$collision_message" "$collision_build/stderr" ||
  fail "colliding Var tags did not name both spellings"

for kind in collision builtin; do
  tagged_build="$BUILD/var-explicit-tag-$kind"
  source="$SOURCE/var-explicit-tag-$kind.x"
  "$X2C" translate --out-dir "$tagged_build" "$source"
  "$CC" -iquote "$ROOT/builds/0/lib" -iquote "$tagged_build" \
    "$tagged_build/var-explicit-tag-$kind.c" \
    -L"$ROOT/builds/0" -lx2c -lm \
    -o "$tagged_build/var-explicit-tag-$kind"

  set +e
  ( "$tagged_build/var-explicit-tag-$kind" \
      >"$tagged_build/stdout" 2>"$tagged_build/stderr"
    child_status=$?
    exit "$child_status"
  ) 2>/dev/null
  tagged_status=$?
  set -e

  test "$tagged_status" -ne 0 ||
    fail "explicit $kind tag claim did not abort"
  test ! -s "$tagged_build/stdout" ||
    fail "explicit $kind tag claim reached main"
done

explicit_collision="Var descriptor: tag <sharedtag> names both"
explicit_collision="$explicit_collision ExplicitCollisionOne"
explicit_collision="$explicit_collision and ExplicitCollisionTwo"
grep -Fq "$explicit_collision" \
  "$BUILD/var-explicit-tag-collision/stderr" ||
  fail "explicit tag collision did not name both participants"
grep -Fq 'Var descriptor: explicit tag <list> is built in' \
  "$BUILD/var-explicit-tag-builtin/stderr" ||
  fail "explicit built-in tag claim did not name the tag"

private_class_build="$BUILD/class-private"
mkdir -p "$private_class_build"
"$X2C" translate --out-dir "$private_class_build" \
  "$SOURCE/class-private-a.x" "$SOURCE/class-private-b.x" \
  "$SOURCE/class-private-main.x"
"$CC" -iquote "$ROOT/builds/0/lib" -iquote "$private_class_build" \
  "$private_class_build/class-private-a.c" \
  "$private_class_build/class-private-b.c" \
  "$private_class_build/class-private-main.c" \
  -L"$ROOT/builds/0" -lx2c -lm -o "$private_class_build/class-private"
"$private_class_build/class-private"

printf 'protocol boundary probes passed\n'
