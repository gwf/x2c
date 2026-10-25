/*  operators.x -- operator types and protocol operations */


// operators

module List _unary(Resolve &r, Var operator, List operand) {
  List lhs = r.c.resolve_expression(operand, r.origin);
  Type lhs_type = lhs.cadr();
  if (lhs_type.car() == <opt-ref> && operator != <!>)
    $fail.expressions_optional_ref_unchecked(r.c, r.origin);
  if (operator == <*> && operand.cadr().car() == <&> &&
      lhs_type.car() != <&>) return lhs;
  if (lhs_type === %(<macro-expr>))
    return source_operator_expression(%(<macro-expr>), %($operator $lhs));
  List lowered = operator == <->
    ? _protocol_operator_expression(r.c, operator, lhs, NULL) : NULL;
  if (lowered) return lowered;
  Type type = lhs_type;
  switch (operator.symbol()) {
    case <!>: type = %(int); break;
    case <*>: {
      Type pointee = type.dereference();
      type = pointee ? pointee : r.c.sym.resolve_key(type).dereference();
      break;
    }
    case <&>: type = type.reference(); break;
    case <~>: case <+>: case <->: {
      type = r.c.sym.resolve_numeric_type(type);
      if (type && type.is_integral()) type = type.promote();
      if (!type && lhs_type && operator == <->)
        $fail.expressions_neg_unsupported(r.c, r.origin, lhs_type);
      if (!type) type = lhs_type;
      break;
    }
  }
  if ((operator == <++> || operator == <-->) &&
      r.c.sym.is_var_type(lhs_type))
    _check_dynamic_target(r.c, lhs, r.origin);
  if ((operator == <++> || operator == <-->) &&
      _builtin_index_lvalue(r.c, lhs)) type = %("Var");
  return source_operator_expression(type, %($operator $lhs));
}

module List _postfix(Resolve &r, Var operator, List operand) {
  operand = r.c.resolve_expression(operand, r.origin);
  Type operand_type = operand.cadr();
  if (operand_type.car() == <opt-ref>)
    $fail.expressions_optional_ref_unchecked(r.c, r.origin);
  if (operand_type === %(<macro-expr>))
    return source_postfix_expression(
      %(<macro-expr>), %($operator $operand));
  if (r.c.sym.is_var_type(operand_type))
    _check_dynamic_target(r.c, operand, r.origin);
  if (_builtin_index_lvalue(r.c, operand)) operand_type = %("Var");
  return source_postfix_expression(
    operand_type, %($operator $operand));
}

module List _conditional(
  Resolve &r, Var operator, List condition, List ontrue, List onfalse) {
  condition = r.c.resolve_expression(condition, r.origin);
  ontrue = r.c.resolve_expression(ontrue, r.origin);
  onfalse = r.c.resolve_expression(onfalse, r.origin);
  Type true_type = ontrue.cadr(), false_type = onfalse.cadr();
  if (condition.cadr() === %(<macro-expr>) ||
      true_type === %(<macro-expr>) ||
      false_type === %(<macro-expr>))
    return source_operator_expression(
      %(<macro-expr>), %($operator $condition $ontrue $onfalse));
  /* Arms of one declared type keep it, so a `Symbol` conditional stays a
     `Symbol` rather than the integer that represents it. */
  Type type = true_type;
  if (true_type.declared() != false_type.declared()) {
    Type left = r.c.sym.resolve_numeric_type(type);
    Type right = r.c.sym.resolve_numeric_type(false_type);
    if (left && right) type = left.widest(right);
    else if (_conditional_joins(r.c, false_type, true_type)) {
      type = false_type;
      ontrue = r.c.convert_expression(ontrue, type);
    }
    else if (_conditional_joins(r.c, true_type, false_type))
      onfalse = r.c.convert_expression(onfalse, type);
  }
  return source_operator_expression(
    type, %($operator $condition $ontrue $onfalse));
}

/* A conditional whose arms are a `Var` and another value is a `Var`: the
   other arm boxes, so C sees one operand type. Other mixed arms keep their
   C types until a target converts each arm. */
static int _conditional_joins(Compiler c, Type type, Type other) =>
  type && other && c.sym.is_var_type(type) && !c.sym.is_var_type(other);

module List _binary(Resolve &r, Var operator, List left, List right) {
  List lhs = r.c.resolve_expression(left, r.origin);
  List rhs = r.c.resolve_expression(right, r.origin);
  return _binary_expression(r.c, operator, lhs, rhs, r.origin);
}

module List _binary_expression(
  Compiler c, Symbol operator, List lhs, List rhs, Token origin) {
  Type lhs_type = lhs.cadr(), rhs_type = rhs.cadr();
  if (lhs_type === %(<macro-expr>) ||
      rhs_type === %(<macro-expr>))
    return source_operator_expression(
      %(<macro-expr>), %($operator $lhs $rhs));
  if (operator.is_assignment_op()) {
    if (operator != <=> &&
        (c.sym.is_var_type(lhs_type) || c.sym.is_var_type(rhs_type)))
      _check_dynamic_target(c, lhs, origin);
    Type type = lhs_type;
    int builtin_index = _builtin_index_lvalue(c, lhs);
    if (builtin_index) type = %("Var");
    /* Meta lowering adapts a callable stored to a Func itself; converting
       here would lift a function name to a hidden global first. */
    if (operator == <=> &&
        !(c.meta_body && c.sym.is_named_value_type(type, "Func")))
      rhs = c.convert_expression(rhs, type);
    return source_operator_expression(type, %($operator $lhs $rhs));
  }
  if (c.rewrite_rules && c.has_rewrites(<binary>, operator)) {
    List source = source_operator_expression(NULL, %($operator $lhs $rhs));
    List rewritten = c.rewrite(
      <binary>, operator, source, <expression>, NULL, origin);
    if (rewritten) return rewritten;
  }
  _convert_string_comparison(c, operator, lhs, rhs);
  int constant_string = _convert_string_addition(c, operator, lhs, rhs);
  List lowered = _protocol_operator_expression(c, operator, lhs, rhs);
  if (lowered) {
    if (!constant_string || c.runtime_literals) return lowered;
    List cached = c.cache(%(string $(c.normalize(lowered))));
    return %(expr ("String") $cached);
  }
  if (operator == <in>)
    $fail.expressions_contains_missing(c, origin, rhs_type);
  /* An untyped preprocessor name beside a converting protocol participant
     would reach the C compiler with no usable conversion. */
  if ((lhs_type != NULL) != (rhs_type != NULL))
    _check_untyped_operand(
      c, operator, lhs_type ? lhs_type : rhs_type,
      lhs_type ? rhs : lhs, origin);
  return _native_binary_expression(c, operator, lhs, rhs, origin);
}

// Built-in indexed mutation returns Var, independently of a read override.
static int _builtin_index_lvalue(Compiler c, List expression) {
  match (expression)
    case %(expr ? (getindex (expr ?receiver_type ?) ?)):
      return !!_x2c_indexed_builtin_helper(c, receiver_type);
  return 0;
}

/* Returns <array> or <map>, including aliases, and zero for other types. */
Symbol _x2c_indexed_builtin_helper(Compiler c, Type type) {
  if (c.sym.is_array_type(type)) return <array>;
  if (c.sym.is_map_type(type)) return <map>;
  return 0;
}

static void _convert_string_comparison(
  Compiler c, Symbol operator, List &lhs, List &rhs) {
  if (operator != <==> && operator != <!=> && operator != <"<"> &&
      operator != <">"> && operator != <"<="> && operator != <">=">)
    return;
  Type lhs_type = lhs.cadr(), rhs_type = rhs.cadr();
  if (c.sym.is_string_type(lhs_type) && _is_raw_string_literal(rhs))
    rhs = c.convert_expression(rhs, lhs_type);
  else if (c.sym.is_string_type(rhs_type) &&
           _is_raw_string_literal(lhs))
    lhs = c.convert_expression(lhs, rhs_type);
}

static int _convert_string_addition(
  Compiler c, Symbol operator, List &lhs, List &rhs) {
  if (operator != <+> || !_is_string_like(c, lhs) ||
      !_is_string_like(c, rhs)) return 0;
  Var matched;
  List bindings;
  /* Bare `%(ident *)` also matches literal data ending in <ident>. */
  int constant =
    !c.needs_resolution(lhs) && !c.needs_resolution(rhs) &&
    !lhs.try_search(
      $source_identifier_content(%((*))), matched, bindings) &&
    !rhs.try_search(
      $source_identifier_content(%((*))), matched, bindings);
  lhs = c.convert_expression(lhs, %("String"));
  rhs = c.convert_expression(rhs, %("String"));
  return constant;
}

static void _check_untyped_operand(
  Compiler c, Symbol operator, Type participant, List other,
  Token origin) {
  Symbol member = c.operator_member(operator);
  if (!member || operator == <==> || operator == <!=>) return;
  if (_converts_operands(c, participant) &&
      c.resolve_protocol_member(participant, member) &&
      other.match(%(expr ? $($source_identifier_content(%(?))))))
    $fail.expressions_operand_untyped(c, origin);
}

/* Operands have been resolved in the caller's current semantic scope. */
static List _native_binary_expression(
  Compiler c, Symbol operator, List lhs, List rhs, Token origin) {
  Type type = _binary_op_type(c, operator, lhs, rhs);
  List operation = source_operator_content(%($operator $lhs $rhs));
  if (c.sym.is_var_type(lhs.cadr()) || c.sym.is_var_type(rhs.cadr()))
    operation = c.anchor_origin(operation, origin);
  return %(expr $type $operation);
}

// operator result types

static List _binary_op_type(
  Compiler c, Symbol op, List lhs, List rhs) {
  _check_optional_operands(c, op, lhs, rhs);
  if (op == <in>) return NULL;
  if (_is_comparison(op)) return %(int);
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (c.sym.is_var_type(ltype) || c.sym.is_var_type(rtype))
    return %("Var");
  switch (op) {
    case <"<<">: case <">>">:
      return _shift_type(c, ltype);
    case </>:    case <%>:
    case <"|">:  case <&>:   case <*>:
    case <^>: return _arithmetic_type(c, ltype, rtype);
    case <+>:    case <->:
      return _binary_op_type_addsub(c, op, lhs, rhs);
    default: return _binary_op_type_fallback(lhs, rhs);
  }
}

static int _is_comparison(Symbol op) {
  switch (op) {
    case <||>:   case <&&>:
    case <==>:   case <!=>:  case <===>:  case <!==>:
    case <"<">:  case <">">: case <"<=">: case <">=">:
      return 1;
  }
  return 0;
}

/* An optional reference is usable only as a truth value or beside a null
   constant in an equality test. */
static void _check_optional_operands(
  Compiler c, Symbol op, List lhs, List rhs) {
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (ltype.car() != <opt-ref> && rtype.car() != <opt-ref>) return;
  int null_test = _null_literal(lhs) || _null_literal(rhs);
  if (!((op == <==> || op == <!=>) && null_test) &&
      op != <&&> && op != <||>)
    $fail.expressions_optional_ref_unchecked(c, c.token);
}

static Type _shift_type(Compiler c, Type lhs) {
  Type scalar = c.sym.resolve_numeric_type(lhs);
  return scalar ? scalar.promote() : NULL;
}

static Type _arithmetic_type(Compiler c, Type lhs, Type rhs) {
  Type left = c.sym.resolve_numeric_type(lhs);
  Type right = c.sym.resolve_numeric_type(rhs);
  return left.widest(right);
}

static List _binary_op_type_addsub(
  Compiler c, Symbol op, List lhs, List rhs) {
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (op == <+> && _is_string_like(c, lhs) &&
      _is_string_like(c, rhs))
    return %("String");
  Type lscalar = c.sym.resolve_numeric_type(ltype);
  Type rscalar = c.sym.resolve_numeric_type(rtype);
  int rpointer = c.sym.resolve_key(rtype).is_pointer();
  if (lscalar) {
    if (rscalar) return lscalar.widest(rscalar);
    else if (op == <+> && rpointer) return rtype;
  }
  else if (c.sym.resolve_key(ltype).is_pointer()) {
    if (rscalar)        return ltype;
    else if (rpointer) return op == <-> ? %("ptrdiff_t") : %(int);
  }
  return NULL;
}

static List _binary_op_type_fallback(List lhs, List rhs) {
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (!ltype) return rtype;
  if (!rtype) return ltype;
  if (ltype === %("Var") || rtype === %("Var")) return %("Var");
  if (ltype.is_pointer()) return ltype;
  if (rtype.is_pointer()) return rtype;
  return NULL;
}

/* protocol operators

   An operator whose operand type adopts the operator's protocol member
   becomes a call of that member. A call result that the member returns
   fresh is discarded by the operator or call that consumes it. */

static List _protocol_operator_expression(
  Compiler c, Symbol op, List lhs, List rhs) {
  Symbol derived = 0;
  List resolved = _resolve_protocol_operator(c, op, lhs, rhs, derived);
  if (!resolved) return NULL;
  (List binding, Type signature) = resolved;
  Type result = signature.cdr(), List arguments = NULL;
  int which = 0;
  if (!rhs) arguments = %($lhs);
  else if (op == <in>) {
    List parameters = signature.car().cadr();
    lhs = c.convert_expression(lhs, parameters.cadr());
    arguments = %($rhs $lhs);
  }
  else arguments = %($lhs $rhs);
  if (op != <in>) {
    if (_is_operator_temporary(c, lhs)) which |= 1;
    if (rhs && _is_operator_temporary(c, rhs)) which |= 2;
  }
  if (!derived && c.resolve_protocol_member(result, "discard"))
    _note_fresh_callee(c, binding);
  if (which) {
    Symbol member = rhs ? c.operator_member(op) : <neg>;
    if (!member) member = c.derived_member(op);
    Type participant = lhs.cadr();
    participant = participant.canonicalize();
    List helper = c.protocol_discard_helper(
      participant, member, which);
    if (helper) (binding, signature) = helper;
  }
  Macro called = $called;
  List callee = %(expr $signature (ident $binding));
  List call = c.rebuild_expression(result, called(callee, arguments));
  if (!derived) return call;
  if (derived == <equal>) return $!int{ !$call };
  List zero = $!int{ 0 };
  return %(expr (int) (op $op $call $zero));
}

/* A binary operator whose one operand is a converting participant converts
   the other operand to that type through its declared converter, so
   `x * 2.0` and `2.0 - x` resolve like `x * two`. The converted operand
   replaces the original through `lhs` and `rhs`. An operand's qualifier
   describes its storage, not the type that adopts the operator, so the
   participant is the unqualified type both here and in the operands'
   comparison. */
static List _resolve_protocol_operator(
  Compiler c, Symbol op, List &lhs, List &rhs, Symbol &derived) {
  derived = 0;
  Type lhs_type = lhs.cadr();
  lhs_type = lhs_type.canonicalize();
  Type participant = lhs_type, rhs_type = NULL;
  if (rhs) {
    rhs_type = rhs.cadr();
    rhs_type = rhs_type.canonicalize();
  }
  Symbol member = 0;
  if (!rhs) {
    if (op != <->) return NULL;
    member = <neg>;
  }
  else if (op == <in>) {
    participant = rhs_type;
    member = <contains>;
  }
  else {
    if (!participant) return NULL;
    member = c.operator_member(op);
    Symbol source = c.derived_member(op);
    if (!member) member = source;
    derived = source;
    if (!member) return NULL;
    // `_comparison` lowers a comparison of two `Var` operands.
    if ((member == <equal> || member == <compare>) &&
        c.sym.is_var_type(participant))
      return NULL;
    if (participant !== rhs_type) {
      participant = _converted_participant(
        c, member, participant, rhs_type, lhs, rhs);
      if (!participant) return NULL;
    }
  }
  return participant && member
       ? c.resolve_protocol_member(participant, member)
       : NULL;
}

static Type _converted_participant(
  Compiler c, Symbol member, Type lhs_type, Type rhs_type,
  List &lhs, List &rhs) {
  if (c.sym.is_var_type(lhs_type) ||
      c.sym.is_var_type(rhs_type)) return NULL;
  Type shared = _shared_participant(c, lhs_type, rhs_type, member);
  if (shared) return shared;
  int lhs_member = !!c.resolve_protocol_member(lhs_type, member) &&
    _converts_operands(c, lhs_type);
  int rhs_member = !!c.resolve_protocol_member(rhs_type, member) &&
    _converts_operands(c, rhs_type);
  if (lhs_member && !rhs_member) {
    List converted = c.converter_call(rhs, rhs_type, lhs_type);
    if (converted) { rhs = converted; return lhs_type; }
  }
  else if (rhs_member && !lhs_member) {
    List converted = c.converter_call(lhs, lhs_type, rhs_type);
    if (converted) { lhs = converted; return rhs_type; }
  }
  return NULL;
}

/* Two different typedef names that share an ancestor meet at the nearest
   one that has `member`, so an alias of `String` compares with a `String`,
   or with another alias, through `String.equal` rather than as the pointers
   C sees. */
static Type _shared_participant(
  Compiler c, Type lhs_type, Type rhs_type, Symbol member) {
  if (!lhs_type.is_bare_typedef_name() || !rhs_type.is_bare_typedef_name())
    return NULL;
  Array lhs_names = _typedef_names(c, lhs_type);
  foreach (Type name in _typedef_names(c, rhs_type))
    if (name in lhs_names &&
        c.resolve_protocol_member(name, member))
      return name;
  return NULL;
}

module Array _typedef_names(Compiler c, Type type) {
  Array names = [];
  int hops = 0;
  for (; type && (type.is_bare_typedef_name() || type.is_typedef());
       type = c.sym.next_typedef(type, hops))
    if (type.is_bare_typedef_name()) names.push(type);
  return names;
}

/* A participant that converts its operator's other operand: a struct or
   union, or a handle typedef pointing at one. Scalar pointers keep native C
   behavior, since `text + 1` must stay pointer arithmetic. */
static int _converts_operands(Compiler c, Type type) {
  Type resolved = c.sym.resolve_key(type);
  if (resolved && resolved.is_pointer())
    resolved = c.sym.resolve_key(resolved.dereference());
  return resolved && resolved.is_aggregate();
}

/* A call result is an unnamed temporary the consuming operator or call may
   discard when its callee is known to return a fresh value: a protocol
   operator member, a converter from a number, or a wrapper of either. The
   callee binding is shared by every call to that function, so the record
   survives the re-resolution that rebuilds call nodes. */
module void _note_fresh_callee(Compiler c, List binding) {
  long identity = (long) binding;
  c.protocol_helpers[%"fresh-callee $identity"] = 1;
}

module int _is_operator_temporary(Compiler c, List expression) {
  match (expression) {
    case %(expr ? $($grouped(?inner))):
      return _is_operator_temporary(c, inner);
  }
  match (expression)
    case $called(%(expr ? $($source_identifier_content(
        %((!set ?binding (*)))))), *arguments):
      return %"fresh-callee $((long) binding.list())" in c.protocol_helpers;
  return 0;
}
