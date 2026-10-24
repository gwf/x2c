/*  expressions.x -- AST transformation expressions */

/** Lowers a resolved lambda expression, under any position wrappers and
    parentheses, through the lambda rule of
    `src/components/lambda-functions.x`;
    other expressions pass through. A noncapturing lambda typed `Func`,
    which only a meta body leaves unlifted, lifts to a `Func` of its native
    signature. */
List Compiler.lower_lambda_expr(Compiler c, List expression) {
  if (expression.car() == <at> || expression.car() == <src>)
    return Ast.rewrite_children(
      expression, %!(List child) => c.lower_lambda_expr(child));
  Macro lambda = $lambda_expression;
  match (expression) {
    case %(expr ?type ${$grouped(?inner)}): {
      List lowered = c.lower_lambda_expr(inner);
      if (lowered == inner) return expression;
      Macro grouped = $grouped;
      return c.rebuild_expression(type, grouped(lowered));
    }
    case %(expr ("Func") ${$lambda_expression(?body, *params)}): {
      Type signature = %((func ${c.lambda_param_types(params)}) "Var");
      return c.lift_func_expression(
        c.rebuild_expression(signature, lambda(body, params)));
    }
    case $source_any_lambda():
      return _shipped_lowering(
        c, <literal>, <lambda>, expression, <expression>, expression.cadr(),
        "lambda");
  }
  return expression;
}

module Ast _slice_node(
  Compiler c, List expression, Type type, List start, List stop, List step) {
  String nominal = NULL;
  match (type)
    case %(?(String name)): nominal = name;
  if (!nominal)
    $fail.transform_slice_unsupported(c, NULL, type, NULL);
  String fnname = %"${nominal}_getslice";
  if (!c.sym.get(%($fnname)))
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
  if (bound.match(%(expr (int) (literal *)))) return bound;
  return %(expr (int) (call "x2c_slice_bound" (args $bound)));
}

/* Access admission has established the getter signature, but its target is
   still intact here. Dispatch before lowering a read or an enclosing
   update. */
static List _access_source(List expression) {
  match (expression) {
    case %(expr ?type (getindex ?base ?key)):
      return %(expr $type (index $base $key));
    case %(expr ?type (parens ?inner)):
      return %(expr $type (parens ${_access_source(inner)}));
  }
  return expression;
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
        source = source_operator_expression(type, %($operator $target $right));
      }
    case %(expr ?type (op (!or ?operator ++ --) ?operand)): {
      List target = _access_source(operand);
      if (target == operand) return NULL;
      kind = <prefix>;
      source = source_operator_expression(type, %($operator $target));
    }
    case %(expr ?type (postfix ?operator ?operand)): {
      List target = _access_source(operand);
      if (target == operand) return NULL;
      kind = <postfix>;
      source = source_postfix_expression(type, %($operator $target));
    }
  }
  return kind ? c.lower_rewrite(
    point, kind, source, <expression>, expression.cadr(), NULL) : NULL;
}

module Ast _expression_node(Compiler c, Ast ast) {
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

/* A left-leaning operator chain nests one (expr (op ...)) level per source
   term, so child-first transformation would recurse once per term. Walk down
   the spine while each level survives its operator rewrites unchanged,
   transform the deepest term, and rebuild upward. Entered only for chain
   heads, with expression rewrites already applied. */
static List _op_chain_first(List ast) {
  match (ast)
    case %(expr ? ?content):
      match (content)
        case $source_operator_content(%(? ?first *rest)):
          if (first is <list>) {
            List operand = first;
            match (operand)
              case %(expr ? ?inner):
                match (inner)
                  case $source_operator_content(%(*parts)):
                    return operand;
          }
  return NULL;
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
      rebuilt = %(expr $type ${_step(c, rewritten)});
      break;
    }
    types.push(type);
    levels.push(ast);
    ast = c.lower_typed_adapter_expr(first);
    ast = c.lower_lambda_expr(ast);
  }
  for (int i = (int) levels.len() - 1; i >= 0; i--)
    match (levels[i].caddr())
      case $source_operator_content(%(?operator ? *rest)): {
        Array parts = [];
        if (operator is <list>) parts.push(_step(c, operator));
        else parts.push(operator);
        parts.push(rebuilt);
        foreach (Var operand in rest) {
          if (operand is <list>) parts.push(_step(c, operand));
          else parts.push(operand);
        }
        rebuilt = source_operator_expression(types[i], parts.list_free());
      }
  return rebuilt;
}

// casts and bracket reads

module List _cast(Compiler c, List ast) {
  match (ast)
    case $source_cast_content(
        %((!set ?declarator (decl *parts))
          (!set ?expression (expr ?source_type ?)))): {
      List declaration = %(declare @parts);
      Type type = declaration.type_from_ast();
      List operand = expression;
      if (operand.match(%(expr ? (composite *)))) {
        Type native = type;
        match (declaration)
          case %(declare ?base (bindings (bind ? ?mods))):
            native = mods.list().append(base);
        return c.convert_compound_literal(operand, type, native);
      }
      int source_var = c.sym.is_var_type(source_type);
      int target_var = c.sym.is_var_type(type);
      int unresolved = 0;
      match (expression)
        case %(expr () ${$source_identifier_content(%(?name))}):
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
    case $source_cast_content(%(?target (!set ?value (expr ? (composite *))))):
      return c.convert_compound_literal(value, target, target);
  return ast;
}

// A `Var` subscript of a native pointer or array reads as an integer.
module List _index(Compiler c, List ast) {
  Macro indexed = $indexed;
  match (ast)
    case ${$indexed(?base, %(!set ?selector (expr ?type ?)))}
        if (c.sym.is_var_type(type)): {
      List converted = c.convert_expression(selector, %(long));
      return c.rebuild_expression(NULL, indexed(base, converted)).caddr();
    }
  return ast;
}

// declarations and statements

module List _declaration(Compiler c, List ast) {
  match (ast) {
    case %((!or ?head declare decl) ?target
           (bindings *bound_list)): {
      Array values = [], List new_bind = NULL;
      foreach (Ast binding in bound_list) {
        new_bind = binding;
        match (binding)
          case %(op = (bind ?var ?mods) ?rhs): {
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
                  c.static_init_deps[var] = %($dependency);
          }
        values.push(new_bind);
      }
      List new_bindings = values.list_free();
      return %($head $target (bindings @new_bindings));
    }
  }
  return ast;
}

module List _return(Compiler c, List ast) {
  match (ast)
    case $return_value(?expression): {
      List value = c.convert_expression(expression, source_return_type(ast));
      return source_return_content(%($value));
    }
  return ast;
}

// calls

module List _call(Compiler c, List ast) {
  match (ast)
    case ${$called(?callee, *arguments)}:
      match (callee.cadr()) {
        case %((func ?parameters) *):
          return _typed_call(c, callee, parameters, arguments);
        case %((!or (!quote *) & ^) (func ?parameters) *):
          return _typed_call(c, callee, parameters, arguments);
      }
  return ast;
}

static List _typed_call(
  Compiler c, List callee, List params, List args) {
  String callee_name = NULL;
  match (callee) {
    case %(expr ? ${$source_identifier_content(%(?binding))}):
      callee_name = Ast.binding_spelling(binding);
  }
  int list_varargs = callee_name == "List_list_n";
  if (c.fn_name && _iter_immediate_consumer(callee_name) && args)
    args = cons(c.complete_iter_chain(args.car()), args.cdr());
  Array values = [], int arg_index = 0;
  for (List p = params, a = args; a;
       p = p.cdr(), a = a.cdr(), arg_index++) {
    List param = (p ? p.car().list() : NULL), arg = a.car();
    List expected = param;
    if (list_varargs && arg_index > 0) expected = %("Var");
    if (param && param.car() == <param>) expected = param.type_from_ast();
    arg = c.maybe_adapt_func_arg(arg, expected);
    List converted = expected
      ? c.convert_expression(arg, expected)
      : c.lower_lambda_expr(arg);
    values.push(converted);
  }
  List newargs = values.list_free();
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
