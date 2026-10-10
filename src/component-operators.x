/*  component-operators.x -- dynamic operators and participant indexing

    An operation with a `Var` operand that no protocol member resolved
    lowers to the dynamic runtime. A binary operator boxes both operands
    for `Var.binary`; a compound assignment, increment, or decrement calls
    the update helper of its target's storage, which takes the target's
    address once and stores once. A bracket read, store, or update on a
    protocol participant that no earlier rule took calls the participant's
    indexing member, with each operand evaluated once, in order.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"
#include "component-access.x"

// dynamic operators

macro Expression $dynamic_add(Expr $a, Expr $b) => $a + $b;
macro Expression $dynamic_subtract(Expr $a, Expr $b) => $a - $b;
macro Expression $dynamic_multiply(Expr $a, Expr $b) => $a * $b;
macro Expression $dynamic_divide(Expr $a, Expr $b) => $a / $b;
macro Expression $dynamic_remainder(Expr $a, Expr $b) => $a % $b;
macro Expression $dynamic_left(Expr $a, Expr $b) => $a << $b;
macro Expression $dynamic_right(Expr $a, Expr $b) => $a >> $b;
macro Expression $dynamic_and(Expr $a, Expr $b) => $a & $b;
macro Expression $dynamic_xor(Expr $a, Expr $b) => $a ^ $b;
macro Expression $dynamic_or(Expr $a, Expr $b) => $a | $b;

/* A `Var` operand, or a value `+` beside text or a number combines with. */
meta static int _dynamic_operand(Type type, int text) =>
  type.is_named("Var") || (text ? type.is_text() : !!type.numeric());

$rewrite_typed(Var, $dynamic_add)
$rewrite_typed(Var, $dynamic_subtract)
$rewrite_typed(Var, $dynamic_multiply)
$rewrite_typed(Var, $dynamic_divide)
$rewrite_typed(Var, $dynamic_remainder)
$rewrite_typed(Var, $dynamic_left)
$rewrite_typed(Var, $dynamic_right)
$rewrite_typed(Var, $dynamic_and)
$rewrite_typed(Var, $dynamic_xor)
$rewrite_typed(Var, $dynamic_or)
/** Boxes both operands of an arithmetic, shift, or bitwise operator for
    `Var.binary`, after rejecting an operand that is neither a number nor,
    for `+` beside text, text. The call is returned lowered, because an
    operator chain applies this rule once for each term and binding would
    search the whole remaining chain each time. */
meta Code dynamic_binary(Code code) {
  match (code) case %(expr ? (op ?(Symbol op) ?left ?right)): {
    Code lhs = left, rhs = right;
    Type left_type = lhs.cadr(), right_type = rhs.cadr();
    int text = op == <+> && _dynamic_operand(left_type, 1) &&
      _dynamic_operand(right_type, 1);
    if (!text && (!_dynamic_operand(left_type, 0) ||
                  !_dynamic_operand(right_type, 0))) {
      String left_name = left_type.repr(), right_name = right_type.repr();
      x2c_diagnostic_fail_at(
        NULL, <xform>, "dynamic numeric operators require numeric operands",
        %("operator: $op left type: $left_name right type: $right_name"));
    }
    List callee = %(expr (<macro-expr>) (ident (binding-name "Var_binary")));
    List symbol = %(expr ("Symbol") (literal ("Symbol") ${op.str()} $op));
    List call = %(call $callee (args ${lhs.convert(%("Var"))} $symbol
                                     ${rhs.convert(%("Var"))}));
    return %(code-value "lowered" (expr ("Var") $call) ());
  }
  return code;
}

// dynamic updates

macro Expression $dynamic_add_to(Expr $a, Expr $b) => $a += $b;
macro Expression $dynamic_subtract_from(Expr $a, Expr $b) => $a -= $b;
macro Expression $dynamic_multiply_by(Expr $a, Expr $b) => $a *= $b;
macro Expression $dynamic_divide_by(Expr $a, Expr $b) => $a /= $b;
macro Expression $dynamic_remainder_by(Expr $a, Expr $b) => $a %= $b;
macro Expression $dynamic_left_by(Expr $a, Expr $b) => $a <<= $b;
macro Expression $dynamic_right_by(Expr $a, Expr $b) => $a >>= $b;
macro Expression $dynamic_and_with(Expr $a, Expr $b) => $a &= $b;
macro Expression $dynamic_xor_with(Expr $a, Expr $b) => $a ^= $b;
macro Expression $dynamic_or_with(Expr $a, Expr $b) => $a |= $b;
macro Expression $dynamic_increment(Expr $a) => ++$a;
macro Expression $dynamic_decrement(Expr $a) => --$a;
macro Expression $dynamic_postincrement(Expr $a) => $a++;
macro Expression $dynamic_postdecrement(Expr $a) => $a--;

/* The operation a compound assignment applies before it stores. */
meta static Symbol _dynamic_operation(Symbol assignment) {
  foreach (List row, %((<+=> <+>) (<-=> <->) (<*=> <*>) (</=> </>)
                       (<%=> <%>) (<"<<="> <"<<">) (<">>="> <">>">)
                       (<&=> <&>) (<^=> <^>) (<|=> <|>)))
    if (row.car() == assignment) return row.cadr();
  return 0;
}

/* The `Symbol` argument the update helpers take, as its integer value. */
meta static List _dynamic_symbol(Symbol op) =>
  %(expr ("Symbol") "${(unsigned long) op}");

/* A call of the update `helper` with the address of `target`, which the
   cleanup walk recognizes as a write to `target`. */
meta static Code _dynamic_update(
  Type type, Code target, Symbol op, Code value, String helper) {
  Type target_type = target.cadr(), address_type = %(* @target_type);
  List address = %(expr $address_type (op & (parens $target)));
  List operation = _dynamic_symbol(op);
  List call = value
    ? %(call $helper (args $address $operation $value))
    : %(call $helper (args $address $operation));
  return %(code-value "lowered" (expr $type $call) ());
}

/* The update helper for a target of `type`, which must be numeric and not
   an enum when it is not `Var`. */
meta static String _dynamic_helper(Type type) {
  if (type.is_named("Var")) return "x2c_var_update_volatile";
  Type scalar = type.numeric();
  match (scalar)
    case %(enum *):
      x2c_diagnostic_fail_at(
        NULL, <xform>, "dynamic compound assignment cannot target an enum",
        NULL);
  String helper = type.update_helper();
  if (!helper)
    x2c_diagnostic_fail_at(
      NULL, <xform>, "dynamic compound assignment requires a numeric lvalue",
      %("left type: ${type.repr()}"));
  return helper;
}

$rewrite_typed(Var, $dynamic_add_to)
$rewrite_typed(Var, $dynamic_subtract_from)
$rewrite_typed(Var, $dynamic_multiply_by)
$rewrite_typed(Var, $dynamic_divide_by)
$rewrite_typed(Var, $dynamic_remainder_by)
$rewrite_typed(Var, $dynamic_left_by)
$rewrite_typed(Var, $dynamic_right_by)
$rewrite_typed(Var, $dynamic_and_with)
$rewrite_typed(Var, $dynamic_xor_with)
$rewrite_typed(Var, $dynamic_or_with)
/** Updates a `Var` or numeric lvalue with a `Var` or numeric operand
    through the update helper of its storage. */
meta Code dynamic_compound(Code code) {
  match (code) case %(expr ?(Type type) (op ?(Symbol op) ?left ?right)): {
    Code target = left, rhs = right;
    Type right_type = rhs.cadr();
    Symbol operation = _dynamic_operation(op);
    match (type)
      case %((bitfield *) *):
        x2c_diagnostic_fail_at(
          NULL, <xform>,
          "dynamic compound assignment cannot target a bitfield", NULL);
    if (!right_type.is_named("Var") && !right_type.numeric() &&
        !(operation == <+> && right_type.is_text()))
      x2c_diagnostic_fail_at(
        NULL, <xform>, operation == <+>
          ? "dynamic += requires a numeric, Var, or String operand"
          : "dynamic compound assignment requires a numeric or Var operand",
        %("right type: ${right_type.repr()}"));
    String helper = _dynamic_helper(type);
    return _dynamic_update(
      type, target, operation, rhs.convert(%("Var")), helper);
  }
  return code;
}

$rewrite_typed(Var, $dynamic_increment)
$rewrite_typed(Var, $dynamic_decrement)
$rewrite_typed(Var, $dynamic_postincrement)
$rewrite_typed(Var, $dynamic_postdecrement)
/** Adds or subtracts one through the `Var` update helpers; the postfix
    forms return the value before the change. */
meta Code dynamic_change(Code code) {
  match (code) {
    case %(expr ?(Type type) (op ?(Symbol op) ?target)): {
      Code one = %(expr (int) (literal (int) "1"));
      return _dynamic_update(
        type, target, op == <++> ? <+> : <->, one.convert(%("Var")),
        "x2c_var_update_volatile");
    }
    case %(expr ?(Type type) (postfix ?(Symbol op) ?target)):
      return _dynamic_update(
        type, target, op, NULL, "x2c_var_postfix_volatile");
  }
  return code;
}

macro Expression $dynamic_plus(Expr $a) => +$a;
macro Expression $dynamic_negate(Expr $a) => -$a;
macro Expression $dynamic_complement(Expr $a) => ~$a;

$rewrite_typed(Var, $dynamic_plus)
$rewrite_typed(Var, $dynamic_negate)
$rewrite_typed(Var, $dynamic_complement)
/** Rejects a unary numeric operator on a `Var`. */
meta Code dynamic_unary(Code code) {
  x2c_diagnostic_fail_at(
    NULL, <xform>, "dynamic unary numeric operators are not supported",
    %("use Var.binary with an explicit numeric operand"));
  return code;
}

// participant indexing

/* The bracket shapes are the ones `component-access.x` names; these rules
   follow its collection rules and take any protocol participant. */

$rewrite($indexed)
/** Calls the getter bracket admission selected. */
meta Code indexed_read(Code code) {
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

$rewrite($collection_store)
/** Stores through the participant's `setindex` member. */
meta Code indexed_store(Code code) {
  match (code) case $collection_store(?base, ?key, ?value): {
    Type type = base.cadr();
    /* String is immutable and interned, so an in-place bracket write
       would mutate shared storage and leave its cached header hash
       stale. A raw write bypasses that invariant, while generic setindex
       returns a copy that this assignment would discard. */
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
  return code;
}

/* An update through `updateindex`, or through `postfixindex` without a
   `value`. */
meta static Code _indexed_update(
  Code code, Code base, Code key, Symbol op, Code value) {
  Type type = base.cadr();
  Code member = type.protocol_member(value ? "updateindex" : "postfixindex");
  if (!member) {
    String what = value ? "compound assignment" : "increment or decrement";
    x2c_diagnostic_fail_at(
      NULL, <xform>,
      %"type ${type.repr()} does not support indexed $what", NULL);
  }
  List operation = _dynamic_symbol(op);
  List arguments = value
    ? %($base $key $operation $value) : %($base $key $operation);
  return member.call_in_order(arguments, code.cadr());
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
$rewrite($collection_increment)
$rewrite($collection_decrement)
$rewrite($collection_postincrement)
$rewrite($collection_postdecrement)
/** Updates through the participant's `updateindex` or `postfixindex`
    member. */
meta Code indexed_update(Code code) {
  Code one = %(expr (int) (literal (int) "1"));
  match (code) {
    case $collection_add(?base, ?key, ?value):
      return _indexed_update(code, base, key, <+>, value);
    case $collection_subtract(?base, ?key, ?value):
      return _indexed_update(code, base, key, <->, value);
    case $collection_multiply(?base, ?key, ?value):
      return _indexed_update(code, base, key, <*>, value);
    case $collection_divide(?base, ?key, ?value):
      return _indexed_update(code, base, key, </>, value);
    case $collection_remainder(?base, ?key, ?value):
      return _indexed_update(code, base, key, <%>, value);
    case $collection_and(?base, ?key, ?value):
      return _indexed_update(code, base, key, <&>, value);
    case $collection_or(?base, ?key, ?value):
      return _indexed_update(code, base, key, <|>, value);
    case $collection_xor(?base, ?key, ?value):
      return _indexed_update(code, base, key, <^>, value);
    case $collection_left(?base, ?key, ?value):
      return _indexed_update(code, base, key, <"<<">, value);
    case $collection_right(?base, ?key, ?value):
      return _indexed_update(code, base, key, <">>">, value);
    case $collection_increment(?base, ?key):
      return _indexed_update(code, base, key, <+>, one);
    case $collection_decrement(?base, ?key):
      return _indexed_update(code, base, key, <->, one);
    case $collection_postincrement(?base, ?key):
      return _indexed_update(code, base, key, <++>, NULL);
    case $collection_postdecrement(?base, ?key):
      return _indexed_update(code, base, key, <-->, NULL);
  }
  return code;
}
