/*  component-operators.x -- dynamic operators

    An operation with a `Var` operand that no protocol member resolved
    lowers to the dynamic runtime. A binary operator boxes both operands
    for `Var.binary`; a compound assignment, increment, or decrement calls
    the update helper of its target's storage, which takes the target's
    address once and stores once.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"

// dynamic operators

/* A `Var` operand, or a value `+` beside text or a number combines with. */
meta static int _dynamic_operand(Type type, int text) =>
  type.is_named("Var") || (text ? type.is_text() : !!type.numeric());

$rewrite_operators(Var, <binary>, <+>, <->, <*>, </>, <%>, <"<<">, <">>">,
  <&>, <^>, <|>)
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

$rewrite_operators(Var, <binary>, <+=>, <-=>, <*=>, </=>, <%=>, <"<<=">,
  <">>=">, <&=>, <^=>, <|=>)
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

$rewrite_operators(Var, <prefix>, <++>, <-->)
$rewrite_operators(Var, <postfix>, <++>, <-->)
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

$rewrite_operators(Var, <prefix>, <+>, <->, <~>)
/** Rejects a unary numeric operator on a `Var`. */
meta Code dynamic_unary(Code code) {
  x2c_diagnostic_fail_at(
    NULL, <xform>, "dynamic unary numeric operators are not supported",
    %("use Var.binary with an explicit numeric operand"));
  return code;
}
