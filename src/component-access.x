/* Array/Map mutation policy; getter resolution remains with admission. */
#pragma once
#include "rewrite.x"
#include "grammar.x"

macro Expression $collection_store(Expr $base, Expr $key, Expr $value) =>
  $base[$key] = $value;
macro Expression $collection_add(Expr $base, Expr $key, Expr $value) =>
  $base[$key] += $value;
macro Expression $collection_subtract(Expr $base, Expr $key, Expr $value) =>
  $base[$key] -= $value;
macro Expression $collection_multiply(Expr $base, Expr $key, Expr $value) =>
  $base[$key] *= $value;
macro Expression $collection_divide(Expr $base, Expr $key, Expr $value) =>
  $base[$key] /= $value;
macro Expression $collection_remainder(Expr $base, Expr $key, Expr $value) =>
  $base[$key] %= $value;
macro Expression $collection_and(Expr $base, Expr $key, Expr $value) =>
  $base[$key] &= $value;
macro Expression $collection_or(Expr $base, Expr $key, Expr $value) =>
  $base[$key] |= $value;
macro Expression $collection_xor(Expr $base, Expr $key, Expr $value) =>
  $base[$key] ^= $value;
macro Expression $collection_left(Expr $base, Expr $key, Expr $value) =>
  $base[$key] <<= $value;
macro Expression $collection_right(Expr $base, Expr $key, Expr $value) =>
  $base[$key] >>= $value;
macro Expression $collection_increment(Expr $base, Expr $key) => ++$base[$key];
macro Expression $collection_decrement(Expr $base, Expr $key) => --$base[$key];
macro Expression $collection_postincrement(Expr $base, Expr $key) =>
  $base[$key]++;
macro Expression $collection_postdecrement(Expr $base, Expr $key) =>
  $base[$key]--;

meta static int _collection_family(Code base) {
  Type type = base.type();
  return type.is_named("Array") ? 1 : type.is_named("Map") ? 2 : 0;
}

$rewrite($collection_store)
/** Selects the adopted collection setter for indexed assignment. */
meta Code collection_store(Code code) {
  match (code) case $collection_store(?base, ?key, ?value): {
    if (!_collection_family(base)) return code;
    Code receiver = base;
    Code setter = receiver.type().protocol_member("setindex");
    if (setter) return $!Var{ $setter($base, $key, $value) };
  }
  return code;
}

meta static Code _collection_update(
  Code base, Code key, Code value, Symbol op) {
  int family = _collection_family(base);
  if (!family || !base.type().protocol_member("updateindex")) return NULL;
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

$rewrite($collection_add)
$rewrite($collection_subtract)
$rewrite($collection_multiply)
$rewrite($collection_divide)
$rewrite($collection_remainder)
$rewrite($collection_and)
$rewrite($collection_or)
$rewrite($collection_xor)
$rewrite($collection_left)
$rewrite($collection_right)
/** Selects collection compound updates and checks accepted operands. */
meta Code collection_update(Code code) {
  match (code) {
    case $collection_add(?base, ?key, ?value):
      return _collection_update(base, key, value, <"+">);
    case $collection_subtract(?base, ?key, ?value):
      return _collection_update(base, key, value, <"-">);
    case $collection_multiply(?base, ?key, ?value):
      return _collection_update(base, key, value, <"*">);
    case $collection_divide(?base, ?key, ?value):
      return _collection_update(base, key, value, <"/">);
    case $collection_remainder(?base, ?key, ?value):
      return _collection_update(base, key, value, <"%">);
    case $collection_and(?base, ?key, ?value):
      return _collection_update(base, key, value, <"&">);
    case $collection_or(?base, ?key, ?value):
      return _collection_update(base, key, value, <"|">);
    case $collection_xor(?base, ?key, ?value):
      return _collection_update(base, key, value, <"^">);
    case $collection_left(?base, ?key, ?value):
      return _collection_update(base, key, value, <"<<">);
    case $collection_right(?base, ?key, ?value):
      return _collection_update(base, key, value, <">>">);
  }
  return code;
}

$rewrite($collection_increment)
$rewrite($collection_decrement)
/** Stores and returns the incremented or decremented collection value. */
meta Code collection_prefix(Code code) {
  match (code) {
    case $collection_increment(?base, ?key):
      return _collection_update(base, key, $!int{1}, <+>);
    case $collection_decrement(?base, ?key):
      return _collection_update(base, key, $!int{1}, <->);
  }
  return code;
}

$rewrite($collection_postincrement)
$rewrite($collection_postdecrement)
/** Stores the updated collection value and returns its previous value. */
meta Code collection_postfix(Code code) {
  Code base, key;
  Symbol op;
  match (code) {
    case $collection_postincrement(?b, ?k): { base = b; key = k; op = <++>; }
    case $collection_postdecrement(?b, ?k): { base = b; key = k; op = <-->; }
    default: return code;
  }
  int family = _collection_family(base);
  if (!family || !base.type().protocol_member("postfixindex")) return code;
  if (family == 1) return $!Var{ Array_postfixindex($base, $key, $op) };
  if (family == 2) return $!Var{ Map_postfixindex($base, $key, $op) };
  return code;
}

// any participant

/* The `Symbol` argument an update member takes, as its integer value. */
meta static List _access_symbol(Symbol op) =>
  %(expr ("Symbol") "${(unsigned long) op}");

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
  List operation = _access_symbol(op);
  List arguments = value
    ? %($base $key $operation $value) : %($base $key $operation);
  return member.call_in_order(arguments, code.cadr());
}

/** Selects the adopted collection setter for indexed assignment, or a
    participant's `setindex` member. */
meta Code access_store(Code code) {
  match (code) case $collection_store(?base, ?key, ?value): {
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

/** Selects collection compound updates and checks accepted operands, or a
    participant's `updateindex` member. */
meta Code access_update(Code code) {
  match (code) {
    case $collection_add(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"+">);
    case $collection_subtract(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"-">);
    case $collection_multiply(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"*">);
    case $collection_divide(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"/">);
    case $collection_remainder(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"%">);
    case $collection_and(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"&">);
    case $collection_or(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"|">);
    case $collection_xor(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"^">);
    case $collection_left(?base, ?key, ?value):
      return _access_update(code, base, key, value, <"<<">);
    case $collection_right(?base, ?key, ?value):
      return _access_update(code, base, key, value, <">>">);
  }
  return code;
}

/* Adds or subtracts one: a collection boxes it, and a participant's member
   converts the integer to its operand. */
meta static Code _access_step(Code code, Code base, Code key, Symbol op) {
  if (!_collection_family(base))
    return _participant_update(
      code, base, key, op, %(expr (int) (literal (int) "1")));
  return _access_update(code, base, key, $!int{1}, op);
}

/** Stores and returns the incremented or decremented element. */
meta Code access_prefix(Code code) {
  match (code) {
    case $collection_increment(?base, ?key):
      return _access_step(code, base, key, <+>);
    case $collection_decrement(?base, ?key):
      return _access_step(code, base, key, <->);
  }
  return code;
}

/** Stores the updated element and returns its previous value. */
meta Code access_postfix(Code code) {
  Code base, key;
  Symbol op;
  match (code) {
    case $collection_postincrement(?b, ?k): { base = b; key = k; op = <++>; }
    case $collection_postdecrement(?b, ?k): { base = b; key = k; op = <-->; }
    default: return code;
  }
  int family = _collection_family(base);
  if (!family || !base.type().protocol_member("postfixindex"))
    return _participant_update(code, base, key, op, NULL);
  if (family == 1) return $!Var{ Array_postfixindex($base, $key, $op) };
  return $!Var{ Map_postfixindex($base, $key, $op) };
}
