/*  operators.x -- AST transformation operators */

// operators

module List _operator(Compiler c, List ast) {
  List truthy = _truthy(c, ast);
  if (truthy != ast) return truthy;
  match (ast) {
    case $source_operator_content(%(?operator
             (!set ?lhs (expr ?lhs_type ?)) (!set ?rhs (expr ?rhs_type ?)))):
      return _binary_operator(c, ast, operator, lhs, lhs_type, rhs, rhs_type);
    case $source_operator_content(%(
             (!or ?operator + - ~)
             (!set ?argument (expr ?argument_type ?)))):
      if (c.sym.is_var_type(argument_type)) {
        List operation = source_operator_content(%($operator $argument));
        return _dynamic(c, <unary>, argument_type, operation);
      }
    case $source_operator_content(%(
             (!or ?operator ++ --)
             (!set ?argument (expr ?argument_type ?)))):
      return _change(c, ast, operator, argument, argument_type, 0);
  }
  return ast;
}

module List _postfix(Compiler c, List ast) {
  match (ast)
    case $source_postfix_content(%(?operator
           (!set ?argument (expr ?argument_type ?)))):
      return _change(c, ast, operator, argument, argument_type, 1);
  return ast;
}

/* `++` and `--` through a protocol member or on a `Var`. A postfix change
   has no right operand and yields the value before the change. */
static List _change(
  Compiler c, List ast, Symbol op, List arg, Type type, int postfix) {
  if (!c.sym.is_var_type(type)) {
    Symbol binary = op == <++> ? <+> : <->;
    List one = $!int{ 1 };
    List updated = postfix
      ? _protocol_update(c, type, binary, arg, NULL, op)
      : _protocol_update(c, type, binary, arg, one, binary);
    return updated ? updated : ast;
  }
  List operation = postfix ? source_postfix_content(%($op $arg))
                           : source_operator_content(%($op $arg));
  return _dynamic(c, <unary>, type, operation);
}

/* An operation with a `Var` operand lowers through the rule a component
   registered for its operator on `Var`, which receives it typed `Var` and
   returns a result of `type`. The rule's replacement normalizes here like
   any other node. */
static List _dynamic(
  Compiler c, Symbol point, Type type, List operation) {
  List kind = operation.car() == <postfix>
    ? %(postfix $(operation.cadr()) ("Var")) : %($(operation.cadr()) ("Var"));
  List rewritten = c.rewrite(
    point, kind, %(expr ("Var") $operation), <expression>, type, NULL);
  return rewritten ? rewritten.caddr() : operation;
}

module List _truthy(Compiler c, List ast) {
  Macro if_then = $if_then, if_else = $if_else;
  Macro while_loop = $while_loop, do_loop = $do_loop;
  Macro for_loop = $for_loop;
  match (ast) {
    case $if_then(?condition, ?yes):
      return c.rebuild_statement(
        if_then(_truthy_expression(c, condition), yes)).cadr();
    case $if_else(?condition, ?yes, ?no):
      return c.rebuild_statement(
        if_else(_truthy_expression(c, condition), yes, no)).cadr();
    case $while_loop(?condition, ?body):
      return c.rebuild_statement(
        while_loop(_truthy_expression(c, condition), body)).cadr();
    case $do_loop(?body, ?condition):
      return c.rebuild_statement(
        do_loop(body, _truthy_expression(c, condition))).cadr();
    case $for_loop(?init, ?condition, ?increment, ?body):
      return c.rebuild_statement(
        for_loop(
          init, _truthy_expression(c, condition), increment,
          body)).cadr();
    case $source_operator_content(%((!or ?operator && ||) ?lhs ?rhs)): {
      List left = _truthy_expression(c, lhs);
      List right = _truthy_expression(c, rhs);
      return source_operator_content(%($operator $left $right));
    }
    case $source_operator_content(%(? ?condition ?ontrue ?onfalse)): {
      List test = _truthy_expression(c, condition);
      return source_operator_content(%(? $test $ontrue $onfalse));
    }
    case $source_operator_content(%(! ?condition)):
      return source_operator_content(%(! $(_truthy_expression(c, condition))));
  }
  return ast;
}

static List _truthy_expression(Compiler c, List expr) {
  if (!expr) return expr;
  List resolved = c.resolve_protocol_member(expr.cadr(), "truth");
  if (!resolved) return expr;
  (List binding, Type signature) = resolved;
  List callee = $!($signature){ $binding };
  return $!int{ $callee($expr) };
}

static List _symbol_expression(Symbol value) =>
  %(expr ("Symbol") "$((unsigned long) value)");

// Inject conversions so assignment RHS matches the annotated LHS type.
static List _assignment(Compiler c, Symbol op, List lhs, List rhs) {
  if (lhs.match(%(expr ? (slice *))))
    $fail.transform_slice_assignment(c, NULL);
  rhs = c.convert_expression(rhs, lhs.cadr());
  return %(op $op $lhs $rhs);
}

static List _comparison(
  Compiler c, List ast, Symbol op, List lhs, Type lhs_type, List rhs,
  Type rhs_type) {
  if (!c.sym.is_var_type(lhs_type) &&
      !c.sym.is_var_type(rhs_type)) {
    if (op == <===>) return %(op == $lhs $rhs);
    if (op == <!==>) return %(op != $lhs $rhs);
    return ast;
  }
  lhs = c.convert_expression(lhs, %("Var"));
  rhs = c.convert_expression(rhs, %("Var"));
  switch (op) {
    case <==>:  return $!int{ x2c_var_equal($lhs, $rhs) }.caddr();
    case <!=>:  return $!int{ !x2c_var_equal($lhs, $rhs) };
    case <===>: return $!int{ x2c_var_identical($lhs, $rhs) }.caddr();
    case <!==>: return $!int{ !x2c_var_identical($lhs, $rhs) };
  }
  List call = %(call "x2c_var_order" (args $lhs $rhs));
  List zero = $!int{ 0 };
  return %(expr (int) (op $op $call $zero));
}

static List _binary_operator(
  Compiler c, List ast, Symbol operator, List lhs, Type lhs_type, List rhs,
  Type rhs_type) {
  Symbol compound = Symbol.compound_operator(operator);
  if (compound)
    return _compound(c, ast, compound, lhs, lhs_type, rhs, rhs_type);
  switch (operator) {
    case <=>: return _assignment(c, operator, lhs, rhs);
    case <==>:  case <!=>:  case <===>: case <!==>:
    case <"<">: case <"<=">: case <">">:  case <">=">:
      return _comparison(c, ast, operator, lhs, lhs_type, rhs, rhs_type);
  }
  /* The dynamic binary operators are exactly those with a compound
     assignment spelling; `Var_binary` accepts the same operators. */
  if (operator.compound_assignment() &&
      (c.sym.is_var_type(lhs_type) || c.sym.is_var_type(rhs_type)))
    return _dynamic(
      c, <binary>, %("Var"), source_operator_content(%($operator $lhs $rhs)));
  return ast;
}

static List _compound(
  Compiler c, List ast, Symbol op, List lhs, Type lhs_type, List rhs,
  Type rhs_type) {
  int lhs_is_var = c.sym.is_var_type(lhs_type);
  if (_x2c_indexed_builtin_helper(c, lhs_type))
    $fail.transform_container_compound(c, NULL, lhs_type);
  /* Without this rejection a nonmatching String compound falls through to
     native pointer arithmetic on an interned String. Concatenation itself
     lowers through the protocol member below like any adopter, resolved
     against canonical String because Var(String) adoption is exact while
     String typedefs still spell the same lvalue. */
  Type member_type = lhs_type;
  if (c.sym.is_string_type(lhs_type)) {
    if (op != <+> || !_string_operand(c, rhs_type))
      $fail.transform_string_compound(c, NULL);
    member_type = %("String");
  }
  if (!lhs_is_var) {
    // A member with no update helper leaves the rule the operand as written.
    List converted = rhs;
    List updated = _protocol_update(c, member_type, op, lhs, converted, op);
    if (updated) return updated;
  }
  if (!lhs_is_var && !c.sym.is_var_type(rhs_type)) return ast;
  List operation = source_operator_content(
    %($(op.compound_assignment()) $lhs $rhs));
  return _dynamic(c, <binary>, lhs_type, operation);
}

static int _string_operand(Compiler c, Type type) =>
  c.sym.is_string_type(type)
      || type.canonicalize().is_char_pointer_like();

static List _protocol_update(
  Compiler c, Type type, Symbol op, List arg, List &?rhs, Symbol spelled) {
  Symbol member = c.operator_member(op);
  if (!member) return NULL;
  String member_name = member;
  List resolved = c.resolve_protocol_member(type, member_name);
  if (!resolved) return NULL;
  if (rhs) {
    List converted = NULL;
    match (resolved)
      case %(? ((func (? ?parameter *)) ?)):
        converted = c.convert_expression(rhs, parameter);
    if (!converted) return NULL;
    rhs = converted;
  }
  String helper = c.protocol_update_helper(type, member_name, !rhs);
  if (!helper) return NULL;
  List spell = _symbol_expression(spelled);
  if (!rhs) return _update_call(arg, spell, NULL, helper);
  List value = rhs;
  return _update_call(arg, spell, value, helper);
}

/* One protocol-member update. `x += y`, `++x`, and `x++` all resolve the
   operator's member on the receiver type, convert the right operand to the
   member's declared parameter, and ask for the update helper. A null `rhs`
   is a postfix update, which reads the receiver before the helper runs.
   The converted operand stays in `*rhs` when no helper exists, so a caller
   continues into the dynamic path with the operand it already built. */
static List _update_call(
  List target, List operator, List value, String helper) {
  Type type = target.cadr();
  List address = %(expr $(type.reference()) (op & (parens $target)));
  return value ? %(call $helper (args $address $operator $value))
               : %(call $helper (args $address $operator));
}
