/*  callbacks.x -- typed native and lambda callback adaptation */

static macro Stmt $fail.callable_callback_direct(Expr $cb) =>
  _fail(
    $cb, "typed callback adapter source must be a direct function",
    %("supported: a free function or Type.method designator"));

static macro Stmt $fail.callable_callback_target(Expr $cb) =>
  _fail($cb, "typed callback adapter target is incomplete", NULL);

static macro Stmt $fail.callable_callback_source(Expr $cb) =>
  _fail($cb, "typed callback adapter source is incomplete", NULL);

static macro Stmt $fail.callable_callback_variadic(Expr $cb) =>
  _fail($cb, "typed callback adapter cannot be variadic", NULL);

static macro Stmt $fail.callable_callback_arity(
  Expr $cb, Expr $target_count, Expr $source_count) {
  String detail = "target has %d parameters; source has %d".printf(
    $target_count, $source_count);
  _fail($cb, "typed callback adapter arity mismatch", %($detail));
}

static macro Stmt $fail.callable_callback_void_return(Expr $cb) =>
  _fail($cb, "typed callback adapter does not support void return", NULL);

static macro Stmt $fail.callable_callback_result(Expr $cb) =>
  _fail($cb, "typed callback adapter return type mismatch", NULL);

static macro Stmt $fail.callable_callback_parameter(
  Expr $cb, Expr $index, Expr $target, Expr $source) {
  String detail = "parameter %d: %s cannot adapt to %s".printf(
    $index + 1, $target.repr(), $source.repr());
  _fail($cb, "typed callback adapter parameter mismatch", %($detail));
}

// callback adapters

/* A direct function adapted to a callback signature. The helper converts
   each callback argument to the source parameter type, calls the source,
   and converts its result to the callback result. */
static typedef struct Callback {
  Compiler c;
  Type target, source, result, source_result;
  List params, source_params, source_binding;
} Callback;

/** Lowers a resolved `tadapt` expression to a typed callback helper.
    `expression` must have the resolved shape
    `(expr TARGET (tadapt ORIGIN (expr SOURCE (ident BINDING))))`.
    Compatible helpers are cached by source binding and target type, queued
    with `Compiler.add_early`, and returned as typed identifiers; other
    expressions pass through unchanged.
*/
List Compiler.lower_typed_adapter_expr(Compiler c, List expression) {
  match (expression)
    case %(expr ?spelling (tadapt ?at (expr ?source ?payload))): {
      Callback cb = {.c = c};
      cb.source = source;
      match (payload) case %(ident ?binding): cb.source_binding = binding;
      with (c.origin = at) {
        cb.target = c.sym.resolve_key(spelling);
        _split(cb);
        _check_signature(cb);
        _check_params(cb);
        return _publish_typed(cb, spelling);
      }
    }
  return expression;
}

/* The source is a direct function, and both signatures are complete and
   fixed. */
static void _split(Callback &c) {
  Type source = c.source;
  if (!c.source_binding || !source || source.is_pointer() ||
      !source.is_function())
    $fail.callable_callback_direct(c);
  if (!c.target.function_parts(c.params, c.result))
    $fail.callable_callback_target(c);
  if (!source.function_parts(c.source_params, c.source_result))
    $fail.callable_callback_source(c);
  if (_typed_params_variadic(c.params) ||
      _typed_params_variadic(c.source_params))
    $fail.callable_callback_variadic(c);
}

static void _check_signature(Callback &cb) {
  int target_count = cb.params.len(), source_count = cb.source_params.len();
  // lint: allow one-statement-braces ST-1: macro emits declaration and call
  if (target_count != source_count) {
    $fail.callable_callback_arity(cb, target_count, source_count);
  }
  cb.result = cb.result.canonicalize();
  cb.source_result = cb.source_result.canonicalize();
  if (cb.result === %(void) || cb.source_result === %(void))
    $fail.callable_callback_void_return(cb);
  if (cb.result != cb.source_result)
    $fail.callable_callback_result(cb);
}

static void _check_params(Callback &cb) {
  int index = 0;
  List targets = cb.params, sources = cb.source_params;
  for (; targets;
       targets = targets.cdr(), sources = sources.cdr(), index++) {
    Type target = targets.car();
    Type source = sources.car();
    if (_allows(cb, target, source)) continue;
    $fail.callable_callback_parameter(cb, index, target, source);
  }
}

// Permit matching parameter types and one dynamic extraction.
static int _allows(Callback &cb, Type target, Type source) {
  target = target.canonicalize();
  source = source.canonicalize();
  if (target == source) return 1;
  alias cb.c.sym {
    if (_.is_var_type(target) && _.is_var_type(source)) return 1;
    if (!_.is_var_type(target)) return 0;
    if (_.is_named_value_type(source, "Symbol")) return 1;
    return _.resolve_key(source).is_pointer();
  }
}

static void _fail(Callback &cb, String message, List details) {
  _adapter_error(cb.c, message, cb.target, cb.source, details);
}

static List _publish_typed(Callback &cb, Type spelling) {
  Compiler c = cb.c;
  List key = %(tadapt ${cb.source_binding} ${cb.target}), binding = NULL;
  $adapter.memo(c, key, binding) {
    binding = c.sym.introduce(c.fresh_name("callback_adapt"));
    List function = _function(cb, binding);
    c.set_fact(%(function $binding), 1);
    c.add_early(function);
  }
  return _func_bound(spelling, binding);
}

/* The helper `binding` names: each argument converts to its source
   parameter, and the source result converts to the callback result. */
static List _function(Callback &cb, List binding) {
  Compiler c = cb.c;
  (List declarations, List arguments) = c.forward_parameters(cb.params);
  List source = $!(${cb.source}){ ${cb.source_binding} };
  List call = _func_call(
    c, cb.source.apply().canonicalize(), source, arguments);
  List body = cb.result === %(void) ? %((stmnt $call))
    : %((return ${cb.result} ${c.convert_expression(call, cb.result)}));
  return c.wrapper_function(
    %(static @{cb.result}), binding, declarations, body);
}

/** Adapts a lowered noncapturing lambda helper to a typed callback.
    `argument` must be a resolved helper reference produced by
    `Compiler.lower_lambda_expr`, optionally wrapped in parentheses.
    `expected_type` must describe a fixed, nonvariadic function. Unless its
    parameters and result are already `Var`,
    a queued static helper converts callback arguments to the lowered lambda's
    original parameter types before calling it, then converts its `Var` result
    to the expected return type. Already compatible or unsupported shapes pass
    through unchanged.
*/
List Compiler.adapt_lambda_arg(Compiler c, List argument, List expected_type) {
  Callback cb = {.c = c, .target = expected_type};
  match (argument) {
    case %(expr ? ${$grouped(?inner)}): {
      List adapted = c.adapt_lambda_arg(inner, expected_type);
      if (adapted == inner) return argument;
      Macro grouped = $grouped;
      return c.rebuild_expression(expected_type, grouped(adapted));
    }
    case %(expr ?type ${$source_identifier_content(%(?binding))}): {
      cb.source = type;
      cb.source_binding = binding;
    }
    default: return argument;
  }
  List raw_params = NULL, Var return_type = void;
  if (!_lambda_adapter_signature(expected_type, raw_params, return_type) ||
      _typed_params_variadic(raw_params))
    return argument;
  int all_var = _collect_param_types(raw_params, cb.params);
  List source_params = NULL;
  cb.source.function_parts(source_params, NULL);
  _collect_param_types(source_params, cb.source_params);
  List result = return_type is <list> ? return_type : %( $return_type );
  if (all_var && result === %("Var")) return argument;
  cb.result = result;
  return _publish_lambda(cb);
}

static List _publish_lambda(Callback &cb) {
  Compiler c = cb.c;
  List binding = c.sym.introduce(c.fresh_name("lambda_adapt"));
  c.add_early(_function(cb, binding));
  return _func_bound(cb.target, binding);
}

static int _lambda_adapter_signature(
  List expected_type, List &raw_params, Var &return_type) {
  Type expected = expected_type;
  List signature = expected.canonicalize();
  match (signature) case %((!or (!quote *) & ^) *rest): signature = rest;
  match (signature)
    case %((func (*parameters)) ?return_head *): {
      raw_params = parameters;
      return_type = return_head;
      return 1;
    }
  return 0;
}

static int _collect_param_types(List raw_params, List &out_types) {
  Array types = [], int all_var = 1;
  foreach(Var entry in raw_params) {
    Var ptype = entry;
    match (entry)
      case %(param ? ?): ptype = entry.list().type_from_ast();
    List ptype_list = ptype is <list> ? ptype : %( $ptype );
    types.push(ptype_list);
    if (all_var && ptype_list != %("Var")) all_var = 0;
  }
  out_types = types.list_free();
  return all_var;
}
