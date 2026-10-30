/*  expressions.x -- AST transformation expressions */

/** Lowers a resolved lambda expression, under any position wrappers and
    parentheses, through the lambda rule of
    `src/components/lambda-functions.x`;
    other expressions pass through. A noncapturing lambda typed `Func`,
    which only a meta body leaves unlifted, lifts to a `Func` of its native
    signature.
*/
List Compiler.lower_lambda_expr(Compiler c, List expression) {
  if (expression.car() == <at> || expression.car() == <src>)
    return Ast.rewrite_children(
      expression, %!(List child) => c.lower_lambda_expr(child));
  Macro lambda = $lambda_expression;
  match (expression) {
    case %(expr ?type $($grouped(?inner))): {
      List lowered = c.lower_lambda_expr(inner);
      if (lowered == inner) return expression;
      Macro grouped = $grouped;
      return c.rebuild_expression(type, grouped(lowered));
    }
    case %(expr ("Func") $($lambda_expression(?body, *params))): {
      Type signature = %((func $(c.lambda_param_types(params))) "Var");
      return c.lift_func_expression(
        c.rebuild_expression(signature, lambda(body, params)));
    }
    case $Ast.lambda_pattern():
      return _shipped_lowering(
        c, <literal>, <lambda>, expression, <expression>, expression.cadr(),
        "lambda");
  }
  return expression;
}

// calls

/** Preserves the fixed arguments for `params`, which ends in a rest
    parameter, and packs the remaining `args` into its container. A List
    tail uses ordinary List construction, where only an explicit splice
    contributes more than one element. A Map tail holds `key: value` entries
    and Map splices; later entries win. The caller changes the callee's
    final parameter to the container before issuing this packed call.
*/
List Compiler.pack_rest_arguments(Compiler c, List params, List args) {
  if (args ~= %((expr (void) ()))) args = NULL;
  int fixed = params.len() - 1;
  if (args.len() < fixed)
    c.report_error(<xform>, "too few arguments for rest function",
      NULL, NULL);
  Array prefix = [];
  for (int i = 0; i < fixed; i++, args = args.cdr()) {
    _require_rest(c, args.car());
    prefix.push(args.car());
  }
  auto Array elements = args.array();
  if (Type.rest_container(params.last()) == %("Map"))
    prefix.push(_map_tail(c, elements));
  else {
    foreach (List element in elements)
      if (element ~= %(expr ? (map-entry ? ?))) _entry_without_map(c);
    prefix.push(c.list_expression(elements, %(nil)));
  }
  return prefix.list_free();
}

// expression lowering

/* A splice or entry outside a rest tail has no container to enter. */
static void _require_rest(Compiler c, List argument) {
  if (argument ~= %(expr ? (splice ?)))
    c.report_error(<xform>, "splice requires a rest argument", NULL, NULL);
  if (argument ~= %(expr ? (map-entry ? ?))) _entry_without_map(c);
}

static void _entry_without_map(Compiler c) =>
  c.report_error(<xform>, "key: value argument requires a Map rest parameter",
    NULL, NULL);

module Ast _slice_node(
  Compiler c, List expression, Type type, List start, List stop, List step) {
  String nominal = NULL;
  if (type ~= %(?(String name))) nominal = name;
  if (!nominal)
    $fail.transform_slice_unsupported(c, NULL, type, NULL);
  String fnname = %"$(nominal)_getslice";
  if (!c.sym.get($(fnname)))
    $fail.transform_slice_unsupported(c, NULL, type, %());
  start = _slice_bound(start);
  stop = _slice_bound(stop);
  step = step ? step : %(literal (int) "1");
  return _step(c, %(call "$fnname" (args $expression $start $stop $step)));
}

/* INT_MIN marks an omitted bound, so any bound but an int literal passes
   through `x2c_slice_bound` to keep its own meaning. */
static List _slice_bound(List bound) {
  if (!bound) return %(literal (int) "-2147483648");
  if (bound ~= %(expr (int) (literal *))) return bound;
  return %(expr (int) (call "x2c_slice_bound" (args $bound)));
}

module Ast _expression_node(Compiler c, Ast ast) {
  if (_pattern_condition(ast)) return _step(c, _condition_value(c, ast));
  Var content = ast.caddr();
  if (content is <list> && content.list().car() == <var>)
    return _step(c, _to_var(c, content.list().cadr()));
  List rewritten = _expression_rewrite(c, ast);
  if (rewritten) return rewritten;
  Ast expression = c.lower_typed_adapter_expr(ast);
  expression = c.lower_lambda_expr(expression);
  if (_op_chain_first(expression)) return _op_chain(c, expression);
  if (expression != ast) return _step(c, expression);
  return _default_node(c, expression);
}

/* Access and call rules see a typed expression before its children lower.
   A call is keyed by the spelling of its callee. */
static List _expression_rewrite(Compiler c, List expression) {
  if (!c.rewrite_rules) return NULL;
  Symbol point = <access>;
  Var kind = 0;
  List source = expression;
  match (expression) {
    case %(expr ? (call (expr ? (ident ?binding)) ?)): {
      point = <call>;
      kind = Ast.binding_spelling(binding);
    }
    case %(expr ? (getindex ? ?)): {
      kind = <read>;
      source = _access_source(expression);
    }
    case %(expr ?type (op ?operator ?left ?right)):
      if (operator.symbol().is_assignment_op()) {
        List target = _access_source(left);
        if (target == left) return NULL;
        kind = operator;
        source = %(expr $type (op $operator $target $right));
      }
    case %(expr ?type (op (!or ?operator ++ --) ?operand)): {
      List target = _access_source(operand);
      if (target == operand) return NULL;
      kind = <prefix>;
      source = %(expr $type (op $operator $target));
    }
    case %(expr ?type (postfix ?operator ?operand)): {
      List target = _access_source(operand);
      if (target == operand) return NULL;
      kind = <postfix>;
      source = %(expr $type (postfix $operator $target));
    }
  }
  return kind ? c.lower_rewrite(
    point, kind, source, <expression>, expression.cadr(), NULL) : NULL;
}

/* Access admission has established the getter signature, but its target is
   still intact here. Dispatch before lowering a read or an enclosing
   update. */
static List _access_source(List expression) {
  match (expression) {
    case %(expr ?type (getindex ?base ?key)):
      return %(expr $type (index $base $key));
    case %(expr ?type (parens ?inner)):
      return %(expr $type (parens $(_access_source(inner))));
  }
  return expression;
}

static Ast _op_chain(Compiler c, Ast ast) {
  Array levels = auto [];
  Array types = auto [];
  Ast rebuilt = NULL;
  for (;;) {
    List first = _op_chain_first(ast);
    if (!first) {
      rebuilt = _finish(c, ast);
      break;
    }
    Var type = ast.cadr();
    if (type is <list>) type = _step(c, type);
    List opnode = ast.caddr();
    List rewritten = _operator(c, opnode);
    if (rewritten != opnode) {
      rebuilt = %(expr $type $(_step(c, rewritten)));
      break;
    }
    types.push(type);
    levels.push(ast);
    ast = c.lower_typed_adapter_expr(first);
    ast = c.lower_lambda_expr(ast);
  }
  for (int i = (int) levels.len() - 1; i >= 0; i--)
    if (levels[i].caddr() ~= %(op ?operator ? *rest)) {
      Array parts = [];
      if (operator is <list>) parts.push(_step(c, operator));
      else parts.push(operator);
      parts.push(rebuilt);
      foreach (Var operand in rest) {
        if (operand is <list>) parts.push(_step(c, operand));
        else parts.push(operand);
      }
      rebuilt = %(expr $(types[i]) (op @(parts.list_free())));
    }
  return rebuilt;
}

/* A left-leaning operator chain nests one (expr (op ...)) level per source
   term, so child-first transformation would recurse once per term. Walk down
   the spine while each level survives its operator rewrites unchanged,
   transform the deepest term, and rebuild upward. Entered only for chain
   heads, with expression rewrites already applied. */
static List _op_chain_first(List ast) {
  if (ast ~= %(expr ? ?content) &&
      content ~= %(op ? ?first *rest) &&
      first is <list>) {
    List operand = first;
    if (operand ~= %(expr ? ?inner) &&
        inner ~= %(op *parts))
      return operand;
  }
  return NULL;
}

// casts and bracket reads

module List _cast(Compiler c, List ast) {
  match (ast)
    case %(cast (!set ?declarator (decl *parts))
          (!set ?expression (expr ?source_type ?))): {
      List declaration = %(declare @parts);
      Type type = declaration.type_from_ast();
      List operand = expression;
      if (operand ~= %(expr ? (composite *))) {
        Type native = type;
        if (declaration ~= %(declare ?base (bindings (bind ? ?mods))))
          native = mods.list().append(base);
        return c.convert_compound_literal(operand, type, native);
      }
      int source_var = c.sym.is_var_type(source_type);
      int target_var = c.sym.is_var_type(type);
      int unresolved = 0;
      if (expression ~= %(expr () (ident ?name)))
        unresolved = 1;
      int target_func = source_type &&
        c.sym.resolve_key(type) === c.sym.resolve_key(%("Func"));
      if (type !== %(void) &&
          (source_var || target_func ||
           (target_var && (source_type || unresolved))))
        return c.convert_expression(expression, type);
      return %(cast $type $expression);
    }
  match (ast)
    case %(cast ?target (!set ?value (expr ? (composite *)))):
      return c.convert_compound_literal(value, target, target);
  return ast;
}

// A `Var` subscript of a native pointer or array reads as an integer.
module List _index(Compiler c, List ast) {
  Macro indexed = $indexed;
  if (ast ~= $($indexed(?base, %(!set ?selector (expr ?type ?)))) &&
      c.sym.is_var_type(type)) {
    List converted = c.convert_expression(selector, %(long));
    return c.rebuild_expression(NULL, indexed(base, converted)).caddr();
  }
  return ast;
}

// declarations and statements

module List _declaration(Compiler c, List ast) {
  if (ast ~= %((!or ?head declare decl) ?target
      (bindings *bound_list))) {
    Array values = [];
    foreach (Ast binding in bound_list) {
      Ast new_bind = binding;
      if (binding ~= %(op = (bind ?var ?mods) ?rhs)) {
        Type target_type = %(declare $target
          (bindings (bind $var $mods))).type_from_ast();
        List native_target = $!($target_type){ $var };
        List converted = c.convert_initializer(
          rhs, target_type, native_target);
        new_bind = %(op = (bind $var $mods) $converted);
        if (target_type.type().is_static())
          match (converted)
            case %(expr ("Func")
                   (ident (!set ?dependency (binding ? ?)))):
              c.static_init_deps[var] = $(dependency);
      }
      values.push(new_bind);
    }
    List new_bindings = values.list_free();
    return %($head $target (bindings @new_bindings));
  }
  return ast;
}

module List _return(Compiler c, List ast) {
  if (ast ~= %(return ?type ?expression)) {
    List value = c.convert_expression(expression, type);
    return %(return $value);
  }
  return ast;
}

module List _call(Compiler c, List ast) {
  if (ast ~= $($called(?callee, *arguments))) {
    match (callee.cadr()) {
      case %((func ?parameters) *):
        return _typed_call(c, callee, parameters, arguments);
      case %((!or (!quote *) & ^) (func ?parameters) *):
        return _typed_call(c, callee, parameters, arguments);
    }
    Type type = callee.cadr();
    if (!type) return ast;
    Type resolved = c.sym.resolve_key(type);
    List parameters = NULL;
    if (resolved.rest_index() >= 0 &&
        resolved.function_parts(parameters, NULL)) {
      callee = %(expr $resolved $(callee.caddr()));
      return _typed_call(c, callee, parameters, arguments);
    }
  }
  return ast;
}

module List _typed_call(
  Compiler c, List callee, List params, List args) {
  List supplied = args;
  if (args === %((expr (void) ()))) args = NULL;
  String callee_name = NULL;
  if (callee ~= %(expr ? (ident ?binding)))
    callee_name = Ast.binding_spelling(binding);
  int list_varargs = callee_name == "List_list_n";
  if (c.fn_name && _iter_immediate_consumer(callee_name) && args)
    args = cons(c.complete_iter_chain(args.car()), args.cdr());
  Array values = [], int arg_index = 0;
  List p = params, a = args;
  for (; a; p = p.cdr(), a = a.cdr(), arg_index++) {
    List param = p ? p.car().list() : NULL;
    if (Type.rest_container(param)) break;
    List arg = a.car();
    _require_rest(c, arg);
    List expected = param;
    if (list_varargs && arg_index > 0) expected = %("Var");
    if (param && param.car() == <param>) expected = param.type_from_ast();
    arg = c.maybe_adapt_func_arg(arg, expected);
    List converted = expected
      ? c.convert_expression(arg, expected)
      : c.lower_lambda_expr(arg);
    values.push(converted);
  }
  List rest = p;
  while (rest && !Type.rest_container(rest.car())) rest = rest.cdr();
  if (rest) {
    Type container = Type.rest_container(rest.car());
    List packed = c.pack_rest_arguments(p, a).car();
    packed = c.maybe_adapt_func_arg(packed, container);
    values.push(c.convert_expression(packed, container));
    List native = params[0:arg_index].append($(container));
    Type signature = callee.cadr();
    if (signature.is_pointer())
      signature = cons(signature.car(),
        cons(%(func $native), signature.cdr().cdr()));
    else signature = cons(%(func $native), signature.cdr());
    callee = %(expr $signature $(callee.caddr()));
  }
  List newargs = values.list_free();
  if (!newargs) newargs = supplied;
  Macro called = $called;
  return c.rebuild_expression(NULL, called(callee, newargs)).caddr();
}

static int _iter_immediate_consumer(String name) =>
  name == "Iter_try_next" || name == "Iter_next" ||
         name == "Iter_list" || name == "Iter_array" ||
         name == "Iter_foldl" || name == "Iter_any" ||
         name == "Iter_parallel_map" || name == "Iter_parallel_map_in" ||
         name == "Iter_all" || name == "Iter_find" ||
         name == "Iter_count" || name == "Iter_sum" ||
         name == "Iter_product" || name == "Iter_min" ||
         name == "Iter_max";

module List _to_var(Compiler c, List expr) =>
  c.convert_expression(expr, %("Var"));
