/* Array/Map mutation policy; getter resolution remains with admission. */
#pragma once
#include "rewrite.x"

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
macro Expression $collection_postincrement(Expr $base, Expr $key) => $base[$key]++;
macro Expression $collection_postdecrement(Expr $base, Expr $key) => $base[$key]--;

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
    x2c_diagnostic_fail_at(NULL, <xform>, message,
      %("right type: ${type.repr()}"));
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
