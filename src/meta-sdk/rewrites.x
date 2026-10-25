/*  rewrites.x -- compile-time SDK rewrites

    Copyright (c) 2026 Gary William Flake.
*/

static macro Stmt $fail.meta_sdk_rewrite_pattern() =>
  MetaContext.reject("unsupported rewrite pattern", NULL);

static macro Stmt $fail.meta_sdk_initialization_pattern() =>
  MetaContext.reject("after-initialization requires a declaration pattern", NULL);

/* Default holes retain the macro's declared capture names and cardinality. */
static List _rewrite_holes(Macro shape, List supplied) {
  if (supplied) return supplied;
  Array holes = [];
  foreach (List parameter in shape.assoc(<parameters>).list()) {
    String binder = parameter.assoc(<binder>).str();
    String prefix = parameter.assoc(<sequence>).int() ? "*" : "?";
    holes.push(Atom.intern(prefix + binder[1:]));
  }
  return holes.list_free();
}

/* One rule row for each of `kinds`. */
static Code _rewrite_registration(
  Code function, List shape, List holes, Symbol point, List kinds) {
  String name = Code.name(function);
  Array rows = [];
  foreach (Var kind in kinds)
    rows.push(%(rewrite $point $kind $name $shape $holes));
  return %($(Code.bound(function, rows.list_free())));
}

/* A function pattern is keyed by the return type it spells, or by `<any>`
   when a hole stands there. */
static Var _function_rule_key(Var type) => _ground(type) ? type : <any>;

static int _ground(Var pattern) {
  if (pattern is not <list>)
    return !pattern.is_binder() && !pattern.is_match_op();
  foreach (Var part in pattern.list()) if (!_ground(part)) return 0;
  return 1;
}

/* A Unit macro whose body is its one `Function` hole matches every
   function definition. */
static int _function_hole(Macro shape) {
  List parameters = shape.assoc(<parameters>);
  if (parameters.len() != 1 ||
      parameters.car().list().assoc(<kind>) != <function>)
    return 0;
  match (shape.assoc(<template>)) case %(seq ?only): return only.is_binder();
  return 0;
}

/* The operators an operator position names: one operator, or each of
   `(!or OP...)`, any of them quoted. */
static List _rule_operators(Var position) {
  List operators = %($position);
  match (position) case %((!quote !or) *choices): operators = choices;
  Array found = [];
  foreach (Var operator in operators) {
    match (operator) case %((!quote !quote) ?quoted): operator = quoted;
    found.push(operator);
  }
  return found.list_free();
}

/* Whether an operator pattern types its operation, `type`, or one of
   `operands` with `Var` or an alias of it, which selects the dynamic
   operations. */
static int _rule_dynamic(Var type, List operands) {
  if (_rule_var(type)) return 1;
  foreach (Var operand in operands) {
    match (operand) case %((!quote !and) ?inner): operand = inner;
    match (operand) case %(expr ?operand_type *):
      if (_rule_var(operand_type)) return 1;
  }
  return 0;
}

static int _rule_var(Var type) =>
  type is <list> && active.expander.sym.is_var_type(type);

/* The dynamic family's keys for `operators` in `form`, `op` or `postfix`. */
static List _rule_dynamic_kinds(List operators, Symbol form) {
  Array kinds = [];
  foreach (Symbol operator in operators)
    kinds.push(
      form == <postfix> ? %(postfix $operator ("Var")) : %($operator ("Var")));
  return kinds.list_free();
}

/* `holes` with a receiver hole `(expr MARK *)` matching any receiver. */
static List _unmarked(List holes, Symbol mark) {
  Array kept = [];
  foreach (Var hole in holes)
    kept.push(hole == %(expr $mark *) ? %(expr ? *) : hole);
  return kept.list_free();
}

/** Answers `Code.register_rewrite`, declared in `lib/meta.x`: the
    pattern's form selects the family and its keys. A function rule is
    keyed by return type, which `Compiler.normalize` dispatches once per
    definition before its body lowers. */
Code Code.register_rewrite(Code function, List pattern, List holes) {
  _require_expansion("Code.register_rewrite");
  Macro shape = NULL;
  match (pattern) case %(macrodef *): {
    shape = pattern;
    if (!holes && _function_hole(shape))
      return _rewrite_registration(
        function, shape, %((!and ?function (function *))), <function>,
        %(any));
    holes = _rewrite_holes(shape, holes);
    pattern = shape.pattern(holes);
  }
  Symbol point = 0;
  List kinds = NULL;
  match (pattern) {
    case %(expr ? (index ? ?)): { point = <access>; kinds = %(read); }
    case %(expr ?type (op ?position ?left ?right)): {
      kinds = _rule_operators(position);
      Symbol operator = kinds.car();
      point = operator.is_assignment_op() ? 0 : <binary>;
      match (left) case %(expr ? (index ? ?)):
        if (operator.is_assignment_op()) point = <access>;
      if (_rule_dynamic(type, %($left $right))) {
        point = <binary>;
        kinds = _rule_dynamic_kinds(kinds, <op>);
      }
    }
    case %(expr ? (op ((!quote !quote) (!or ++ --)) (expr ? (index ? ?)))):
      { point = <access>; kinds = %(prefix); }
    case %(expr ? (postfix ? (expr ? (index ? ?)))):
      { point = <access>; kinds = %(postfix); }
    case %(expr ?type ((!or ?form op postfix) ?position ?operand)):
      if (_rule_dynamic(type, %($operand))) {
        point = <unary>;
        kinds = _rule_dynamic_kinds(_rule_operators(position), form);
      }
    case %(expr ? (call (expr ? (op ((!quote !quote) .)
            ((!quote !and) (expr ?type *)) ?)) ?)): {
      point = <member>;
      kinds = %($type);
      if (type is <symbol>) holes = _unmarked(holes, type);
    }
    case %(expr ? (call (expr ? (ident (binding ? ?(String callee)))) ?)):
      { point = <call>; kinds = %($callee); }
    case %(expr ?
           ((!or ?head array map segments dstrasgn lambda) *)):
      { point = <literal>; kinds = %($head); }
    case %((!quote !or)
           ((!or ?head switch try raise match dstrdecl conform)
            *) *):
      { point = <node>; kinds = %($head); }
    case %((!or ?head switch try raise match dstrdecl conform) *):
      { point = <node>; kinds = %($head); }
    case %(stmnt (expr ? (dstrasgn *))): { point = <node>; kinds = %(stmnt); }
    case %(!or (api-source ? ? (function ?type *)) (function ?type *)):
      { point = <function>; kinds = %($(_function_rule_key(type))); }
  }
  if (!point) $fail.meta_sdk_rewrite_pattern();
  return _rewrite_registration(
    function, shape ? shape : pattern, holes, point, kinds);
}

/** Adds post-initialization block items while the declaration owner retains
    the original declarators, their type identity, and initialization order. */
Code Code.register_after_initialization(Code c, Macro shape, List holes) {
  _require_expansion("Code.register_after_initialization");
  holes = _rewrite_holes(shape, holes);
  List pattern = shape.pattern(holes);
  match (pattern) case %(declare *):
    return _rewrite_registration(c, shape, holes, <decl>, %(init));
  $fail.meta_sdk_initialization_pattern();
}
