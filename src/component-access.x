/* Bracket access policy: Array and Map mutation through their typed
   helpers, and any other participant's read, store, and update through
   its indexing members, with each operand evaluated once, in order.
   Getter resolution remains with admission. */
#pragma once
#include "rewrite.x"
#include "grammar.x"

macro Expression $x2c.collection.store(Expr $base, Expr $key, Expr $value) =>
  $base[$key] = $value;
macro Expression $x2c.collection.add(Expr $base, Expr $key, Expr $value) =>
  $base[$key] += $value;
macro Expression $x2c.collection.subtract(
  Expr $base, Expr $key, Expr $value) =>
  $base[$key] -= $value;
macro Expression $x2c.collection.multiply(
  Expr $base, Expr $key, Expr $value) =>
  $base[$key] *= $value;
macro Expression $x2c.collection.divide(Expr $base, Expr $key, Expr $value) =>
  $base[$key] /= $value;
macro Expression $x2c.collection.remainder(
  Expr $base, Expr $key, Expr $value) =>
  $base[$key] %= $value;
macro Expression $x2c.collection.and(Expr $base, Expr $key, Expr $value) =>
  $base[$key] &= $value;
macro Expression $x2c.collection.or(Expr $base, Expr $key, Expr $value) =>
  $base[$key] |= $value;
macro Expression $x2c.collection.xor(Expr $base, Expr $key, Expr $value) =>
  $base[$key] ^= $value;
macro Expression $x2c.collection.left(Expr $base, Expr $key, Expr $value) =>
  $base[$key] <<= $value;
macro Expression $x2c.collection.right(Expr $base, Expr $key, Expr $value) =>
  $base[$key] >>= $value;
macro Expression $x2c.collection.increment(Expr $base, Expr $key) =>
  ++$base[$key];
macro Expression $x2c.collection.decrement(Expr $base, Expr $key) =>
  --$base[$key];
macro Expression $x2c.collection.postincrement(Expr $base, Expr $key) =>
  $base[$key]++;
macro Expression $x2c.collection.postdecrement(Expr $base, Expr $key) =>
  $base[$key]--;

meta static int _collection_family(Code base) {
  Type type = base.type();
  return type.is_named("Array") ? 1 : type.is_named("Map") ? 2 : 0;
}

// participants

$rewrite($indexed)
/** Calls the getter bracket admission selected. */
meta Code access_read(Code code) {
  match (code) case $indexed(?base, ?key): {
    Type type = base.cadr(), result = code.cadr();
    Code getter = type.getter();
    if (!getter)
      x2c_diagnostic_fail_at(
        NULL, <xform>, %"type ${type.repr()} does not support bracket indexing",
        NULL);
    return $!($result){ $getter($base, $key) };
  }
  return code;
}

/* Stores through the participant's `setindex` member. String is immutable
   and interned, so an in-place bracket write would mutate shared storage
   and leave its cached header hash stale. A raw write bypasses that
   invariant, while generic setindex returns a copy that this assignment
   would discard. */
meta static Code _participant_store(
  Code code, Code base, Code key, Code value) {
  Type type = base.cadr();
  if (type.is_named("String")) {
    String note = "String is immutable: use the copy-producing "
                  "String.withindex, or bind a char * to write a "
                  "transient String.malloc buffer";
    x2c_diagnostic_fail_at(
      NULL, <xform>, "String does not support bracket assignment",
      %($note));
  }
  Code setter = type.protocol_member("setindex");
  if (!setter)
    x2c_diagnostic_fail_at(
      NULL, <xform>,
      %"type ${type.repr()} does not support bracket assignment",
      %("use an explicit copy-producing method where available"));
  return setter.call_in_order(%($base $key $value), code.cadr());
}

/* Updates through the participant's `updateindex` member, or through
   `postfixindex` without a `value`. */
meta static Code _participant_update(
  Code code, Code base, Code key, Symbol op, Code value) {
  Type type = base.cadr();
  Code member = type.protocol_member(value ? "updateindex" : "postfixindex");
  if (!member) {
    String what = value ? "compound assignment" : "increment or decrement";
    x2c_diagnostic_fail_at(
      NULL, <xform>,
      %"type ${type.repr()} does not support indexed $what", NULL);
  }
  List operation = $!Symbol{ $op };
  List arguments = value
    ? %($base $key $operation $value) : %($base $key $operation);
  return member.call_in_order(arguments, code.cadr());
}

$rewrite($x2c.collection.store)
/** Selects the adopted collection setter for indexed assignment, or a
    participant's `setindex` member. */
meta Code access_store(Code code) {
  match (code) case $x2c.collection.store(?base, ?key, ?value): {
    Code receiver = base;
    Code setter = _collection_family(base)
      ? receiver.type().protocol_member("setindex") : NULL;
    if (setter) return $!Var{ $setter($base, $key, $value) };
    return _participant_store(code, base, key, value);
  }
  return code;
}

/* A collection's typed update after checking its operand, or a
   participant's `updateindex` member. */
meta static Code _access_update(
  Code code, Code base, Code key, Code value, Symbol op) {
  int family = _collection_family(base);
  if (!family || !base.type().protocol_member("updateindex"))
    return _participant_update(code, base, key, op, value);
  Type type = value.type();
  if (!type.is_named("Var") && !type.numeric() &&
      !(op == <+> && type.is_text())) {
    String message = op == <+>
      ? "indexed += requires a numeric, Var, or String operand"
      : "indexed compound assignment requires a numeric or Var operand";
    x2c_diagnostic_fail_at(
      NULL, <xform>, message, %("right type: ${type.repr()}"));
  }
  if (family == 1) return $!Var{ Array_updateindex($base, $key, $op, $value) };
  return $!Var{ Map_updateindex($base, $key, $op, $value) };
}

$rewrite($x2c.collection.add)
$rewrite($x2c.collection.subtract)
$rewrite($x2c.collection.multiply)
$rewrite($x2c.collection.divide)
$rewrite($x2c.collection.remainder)
$rewrite($x2c.collection.and)
$rewrite($x2c.collection.or)
$rewrite($x2c.collection.xor)
$rewrite($x2c.collection.left)
$rewrite($x2c.collection.right)
/** Selects collection compound updates and checks accepted operands, or a
    participant's `updateindex` member. */
meta Code access_update(Code code) {
  match (code) {
    case $x2c.collection.add(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"+">);
    case $x2c.collection.subtract(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"-">);
    case $x2c.collection.multiply(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"*">);
    case $x2c.collection.divide(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"/">);
    case $x2c.collection.remainder(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"%">);
    case $x2c.collection.and(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"&">);
    case $x2c.collection.or(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"|">);
    case $x2c.collection.xor(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"^">);
    case $x2c.collection.left(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"<<">);
    case $x2c.collection.right(?base, ?key, ?value):
      return _access_update(code, base, key, value, <">>">);
  }
  return code;
}

/* Adds or subtracts one: a collection boxes it, and a participant's member
   converts the integer to its operand. */
meta static Code _access_step(Code code, Code base, Code key, Symbol op) {
  if (!_collection_family(base))
    return _participant_update(code, base, key, op, $!int{ 1 });
  return _access_update(code, base, key, $!int{ 1 }, op);
}

$rewrite($x2c.collection.increment)
$rewrite($x2c.collection.decrement)
/** Stores and returns the incremented or decremented element. */
meta Code access_prefix(Code code) {
  match (code) {
    case $x2c.collection.increment(?base, ?key):
      return _access_step(code, base, key, <+>);
    case $x2c.collection.decrement(?base, ?key):
      return _access_step(code, base, key, <->);
  }
  return code;
}

$rewrite($x2c.collection.postincrement)
$rewrite($x2c.collection.postdecrement)
/** Stores the updated element and returns its previous value. */
meta Code access_postfix(Code code) {
  Code base, key;
  Symbol op;
  match (code) {
    case $x2c.collection.postincrement(?b, ?k):
      { base = b; key = k; op = <++>; }
    case $x2c.collection.postdecrement(?b, ?k):
      { base = b; key = k; op = <-->; }
    default: return code;
  }
  int family = _collection_family(base);
  if (!family || !base.type().protocol_member("postfixindex"))
    return _participant_update(code, base, key, op, NULL);
  if (family == 1) return $!Var{ Array_postfixindex($base, $key, $op) };
  return $!Var{ Map_postfixindex($base, $key, $op) };
}
