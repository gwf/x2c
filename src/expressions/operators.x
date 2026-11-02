/*  operators.x -- operator types and protocol operations */

// operators

/* Returns <array> or <map>, including aliases, and zero for other types. */
Symbol _x2c_indexed_builtin_helper(Compiler c, Type type) {
  if (c.sym.is_array_type(type)) return <array>;
  if (c.sym.is_map_type(type)) return <map>;
  return 0;
}

// operator types and protocol operations

module List _unary(Resolve &r, Var operator, List operand) {
  List lhs = r.c.resolve_expression(operand, r.origin);
  Type lhs_type = lhs.cadr();
  if (lhs_type.is_optional_reference() && operator != <!>)
    $fail.expressions_optional_ref_unchecked(r.c, r.origin);
  if (operator == <*> && operand.cadr().car() == <&> &&
      lhs_type.car() != <&>) return lhs;
  if (lhs_type === %(<macro-expr>))
    return %(expr (<macro-expr>) (op $operator $lhs));
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
  return %(expr $type (op $operator $lhs));
}

module List _postfix(Resolve &r, Var operator, List operand) {
  operand = r.c.resolve_expression(operand, r.origin);
  Type operand_type = operand.cadr();
  if (operand_type.is_optional_reference())
    $fail.expressions_optional_ref_unchecked(r.c, r.origin);
  if (operand_type === %(<macro-expr>))
    return %(expr (<macro-expr>) (postfix $operator $operand));
  if (r.c.sym.is_var_type(operand_type))
    _check_dynamic_target(r.c, operand, r.origin);
  if (_builtin_index_lvalue(r.c, operand)) operand_type = %("Var");
  return %(expr $operand_type (postfix $operator $operand));
}

module List _conditional(
  Resolve &r, Var operator, List condition, List ontrue, List onfalse) {
  condition = r.c.resolve_expression(condition, r.origin);
  ontrue = _resolve_when(r, condition, 1, ontrue);
  onfalse = _resolve_when(r, condition, 0, onfalse);
  Type true_type = ontrue.cadr(), false_type = onfalse.cadr();
  if (condition.cadr() === %(<macro-expr>) ||
      true_type === %(<macro-expr>) ||
      false_type === %(<macro-expr>))
    return %(expr (<macro-expr>) (op $operator $condition $ontrue $onfalse));
  Type type = true_type;
  Type left = r.c.sym.resolve_numeric_type(true_type);
  Type right = r.c.sym.resolve_numeric_type(false_type);
  int same = _conditional_unqualified(true_type.declared()) ==
             _conditional_unqualified(false_type.declared());
  if (left && right) {
    Type widest = left.widest(right);
    if (!same || widest != left) type = widest;
  }
  else if (!same) {
    Type pointer = _conditional_pointer(r.c, ontrue, onfalse);
    if (pointer) type = pointer;
    else if (_conditional_joins(r.c, false_type, true_type)) {
      type = false_type;
      ontrue = r.c.convert_expression(ontrue, type);
    }
    else if (_conditional_joins(r.c, true_type, false_type))
      onfalse = r.c.convert_expression(onfalse, type);
  }
  return %(expr $type (op $operator $condition $ontrue $onfalse));
}

/* C combines the immediate pointee qualifiers of compatible pointers.
   Typedef expansion must retain those qualifiers before comparing bases. */
static Type _conditional_pointer(Compiler c, List lhs, List rhs) {
  Type left = _conditional_unqualified(
    c.sym.normalize_declared_type(lhs.cadr()));
  Type right = _conditional_unqualified(
    c.sym.normalize_declared_type(rhs.cadr()));
  if (left.is_pointer() && _null_literal(c, rhs)) return lhs.cadr();
  if (right.is_pointer() && _null_literal(c, lhs)) return rhs.cadr();
  Type lbase = left.dereference(), rbase = right.dereference();
  if (!lbase || !rbase) return NULL;
  Type base = _conditional_unqualified(lbase);
  Type other = _conditional_unqualified(rbase);
  if (base != other) {
    if (base === %(void) || other === %(void)) base = %(void);
    else return NULL;
  }
  Array qualifiers = [];
  foreach (Type pointee in $(lbase, rbase))
    foreach (Var part in pointee) {
      if (part is not <symbol> || !part.symbol().is_type_qualifier()) break;
      if (!(part in qualifiers)) qualifiers.push(part);
    }
  Type joined = %(* @(qualifiers.list_free()) @base);
  /* Retain the first arm's handle, as before, when it already denotes the
     complete pointer result. A widened pointee cannot use that handle. */
  Type lhs_type = _conditional_unqualified(lhs.cadr().type().declared());
  if (lhs_type.is_bare_typedef_name() && left == joined) return lhs_type;
  return joined;
}

static Type _conditional_unqualified(Type type) {
  while (type.car() is <symbol> && type.car().symbol().is_type_qualifier())
    type = type.cdr();
  return type;
}

/* A conditional whose arms are a `Var` and another value is a `Var`: the
   other arm boxes, so C sees one operand type. Other mixed arms keep their
   C types until a target converts each arm. */
static int _conditional_joins(Compiler c, Type type, Type other) =>
  type && other && c.sym.is_var_type(type) && !c.sym.is_var_type(other);

module List _binary(Resolve &r, Var operator, List left, List right) {
  List lhs = r.c.resolve_expression(left, r.origin);
  List rhs;
  if (operator == <&&>) {
    int scoped = r.c.open_condition_scope(lhs);
    defer { if (scoped) r.c.sym.pop_scope(); }
    rhs = _resolve_when(r, lhs, 1, right);
  }
  else if (operator == <||>) rhs = _resolve_when(r, lhs, 0, right);
  else rhs = r.c.resolve_expression(right, r.origin);
  if (operator == <~=>)
    return r.c.bind_match_condition(lhs, rhs, NULL, r.origin);
  return _binary_expression(r.c, operator, lhs, rhs, r.origin);
}

/* Resolves an operand that runs only when `condition` has truth `holds`. */
static List _resolve_when(
  Resolve &r, List condition, int holds, List operand) {
  List present_before = r.c.assume_condition(condition, holds);
  List resolved = r.c.resolve_expression(operand, r.origin);
  r.c.restore_reference_presence(present_before);
  return resolved;
}

module List _binary_expression(
  Compiler c, Symbol operator, List lhs, List rhs, Token origin) {
  Type lhs_type = lhs.cadr(), rhs_type = rhs.cadr();
  if (lhs_type === %(<macro-expr>) ||
      rhs_type === %(<macro-expr>))
    return %(expr (<macro-expr>) (op $operator $lhs $rhs));
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
    return %(expr $type (op $operator $lhs $rhs));
  }
  if (c.rewrite_rules && c.has_rewrites(<binary>, operator)) {
    List source = %(expr () (op $operator $lhs $rhs));
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
  _check_participant_operand(c, operator, lhs, rhs, origin);
  return _native_binary_expression(c, operator, lhs, rhs, origin);
}

// Built-in indexed mutation returns Var, independently of a read override.
static int _builtin_index_lvalue(Compiler c, List expression) {
  if (expression ~= %(expr ? (getindex (expr ?receiver_type ?) ?)))
    return !!_x2c_indexed_builtin_helper(c, receiver_type);
  return 0;
}

/* A raw string literal beside a String converts for `==` and the
   comparisons derived from `equal` or `compare`. */
static void _convert_string_comparison(
  Compiler c, Symbol operator, List &lhs, List &rhs) {
  if (operator != <==> && !Compiler.derived_member(operator)) return;
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
      %(ident (*)), matched, bindings) &&
    !rhs.try_search(
      %(ident (*)), matched, bindings);
  lhs = c.convert_expression(lhs, %("String"));
  rhs = c.convert_expression(rhs, %("String"));
  return constant;
}

/* An arithmetic operator that no member resolved would reach C as pointer
   arithmetic on a converting participant that has the operator's member,
   so the operand beside it, which did not convert for the member, is an
   error. An untyped preprocessor name has no conversion at all. Equality
   keeps native identity, and a `Var` operand lowers dynamically. */
static void _check_participant_operand(
  Compiler c, Symbol operator, List lhs, List rhs, Token origin) {
  Symbol member = Compiler.operator_member(operator);
  if (!member || operator == <==>) return;
  Type lhs_type = lhs.cadr(), rhs_type = rhs.cadr();
  if (c.sym.is_var_type(lhs_type) || c.sym.is_var_type(rhs_type)) return;
  int left = !!_converting_member(c, lhs_type, member);
  if (!left && !_converting_member(c, rhs_type, member)) return;
  if (!lhs_type || !rhs_type) $fail.expressions_operand_untyped(c, origin);
  $fail.expressions_operand_unconverted(
    c, origin, left ? lhs_type : rhs_type, member,
    left ? rhs_type : lhs_type);
}

/* Operands have been resolved in the caller's current semantic scope. */
static List _native_binary_expression(
  Compiler c, Symbol operator, List lhs, List rhs, Token origin) {
  Type type = _binary_op_type(c, operator, lhs, rhs);
  List operation = %(op $operator $lhs $rhs);
  if (c.sym.is_var_type(lhs.cadr()) || c.sym.is_var_type(rhs.cadr()))
    operation = c.anchor_origin(operation, origin);
  return %(expr $type $operation);
}

// operator result types

static List _binary_op_type(Compiler c, Symbol op, List lhs, List rhs) {
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
  if (!ltype.is_optional_reference() && !rtype.is_optional_reference()) return;
  int null_test = _null_literal(c, lhs) || _null_literal(c, rhs);
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
    if (rscalar) return ltype;
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
  if (!rhs) arguments = $(lhs);
  else if (op == <in>) {
    List parameters = signature.car().cadr();
    lhs = c.convert_expression(lhs, parameters.cadr());
    arguments = $(rhs, lhs);
  }
  else arguments = $(lhs, rhs);
  if (op != <in>) {
    if (_is_operator_temporary(c, lhs)) which |= 1;
    if (rhs && _is_operator_temporary(c, rhs)) which |= 2;
  }
  if (!derived && c.resolve_protocol_member(result, "discard"))
    _note_fresh_callee(c, binding);
  if (which) {
    Symbol member = rhs ? Compiler.operator_member(op) : <neg>;
    if (!member) member = Compiler.derived_member(op);
    Type participant = lhs.cadr();
    participant = participant.canonicalize();
    List helper = c.protocol_discard_helper(participant, member, which);
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

/* A binary operator whose one operand is a converting participant resolves
   that participant's member and converts the other operand for it, so
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
    member = Compiler.operator_member(op);
    Symbol source = Compiler.derived_member(op);
    if (!member) member = source;
    derived = source;
    if (!member) return NULL;
    /* `_comparison` lowers a comparison of two `Var` operands, and the
       dynamic rule lowers their arithmetic through its runtime lanes. */
    if (c.sym.is_var_type(participant)) return NULL;
    if (participant !== rhs_type)
      return _converted_member(c, member, participant, rhs_type, lhs, rhs);
  }
  return participant && member
       ? c.resolve_protocol_member(participant, member)
       : NULL;
}

static List _converted_member(
  Compiler c, Symbol member, Type lhs_type, Type rhs_type,
  List &lhs, List &rhs) {
  if (c.sym.is_var_type(lhs_type) ||
      c.sym.is_var_type(rhs_type)) return NULL;
  Type shared = _shared_participant(c, lhs_type, rhs_type, member);
  if (shared) return c.resolve_protocol_member(shared, member);
  List lhs_member = _converting_member(c, lhs_type, member);
  List rhs_member = _converting_member(c, rhs_type, member);
  if (lhs_member && !rhs_member) {
    Type parameter = _operand_parameter(lhs_member);
    List converted = parameter ? c.convert_expression(rhs, parameter)
                               : c.converter_call(rhs, rhs_type, lhs_type);
    if (converted) { rhs = converted; return lhs_member; }
  }
  else if (rhs_member && !lhs_member && !_operand_parameter(rhs_member)) {
    List converted = c.converter_call(lhs, lhs_type, rhs_type);
    if (converted) { lhs = converted; return rhs_member; }
  }
  return NULL;
}

/* The member of `type` when `type` converts its operator's other operand. */
static List _converting_member(Compiler c, Type type, Symbol member) {
  List resolved = c.resolve_protocol_member(type, member);
  return resolved && _converts_operands(c, type) ? resolved : NULL;
}

/* The operand parameter of `member` when its type differs from the
   receiver's, as `long` does in `T T.add(T, long)`, or NULL. Such a
   member takes the right operand as an ordinary argument, so only a
   participant on the left reaches it; the operator never commutes. */
static Type _operand_parameter(List member) {
  if (member ~= %(? ((func (?(Type receiver) ?(Type parameter))) *)) &&
      parameter.canonicalize() != receiver.canonicalize())
    return parameter;
  return NULL;
}

/* Two different typedef names that share an ancestor meet at the nearest
   one that has `member`, so an alias of `String` compares with a `String`,
   or with another alias, through `String.equal`. C would otherwise compare
   their pointers. */
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
  if (expression ~= $called(%(expr ? (ident (!set ?binding (*)))), *arguments))
    return %"fresh-callee $((long) binding.list())" in c.protocol_helpers;
  return 0;
}
