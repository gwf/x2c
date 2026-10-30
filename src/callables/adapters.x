/*  adapters.x -- FuncAdapter calling convention and helper construction */

static macro Stmt $fail.callable_shared(Expr $c, Expr $source) =>
  _adapter_error(
    $c, "function conversion needs x2c_func_shared from lib/func/func.x",
    %("Func"), $source, NULL);

static macro Stmt $fail.callable_context(Expr $c, Expr $source) =>
  _adapter_error(
    $c,
    "function pointer conversion needs Func.new_context from lib/func/func.x",
    %("Func"), $source, NULL);

static macro Stmt $fail.callable_native_context(
  Expr $c, Expr $target, Expr $source) =>
  _adapter_error(
    $c, "native binding needs Func.context from lib/func/func.x",
    $target, $source, NULL);

static macro Stmt $fail.callable_direct(Expr $c, Expr $target, Expr $source) =>
  _adapter_error(
    $c, "native binding target must be a direct function",
    $target, $source,
    %("supported: a free function or Type.method designator"));

static macro Stmt $fail.callable_variadic(
  Expr $c, Expr $target, Expr $source, Expr $func_type) {
  String message = $c.sym.resolve_key($target) == $func_type
    ? "function conversion to Func cannot be variadic"
    : "native binding target cannot be variadic";
  _adapter_error($c, message, $target, $source, NULL);
}

static macro Stmt $fail.callable_readers(
  Expr $c, Expr $target, Expr $source) =>
  _adapter_error(
    $c, "native binding needs Func argument readers from lib/func/func.x",
    $target, $source, NULL);

static macro Stmt $fail.callable_parameter(
  Expr $c, Expr $target, Expr $source) =>
  _adapter_error(
    $c, "native binding parameter type has no Var representation",
    $target, $source, NULL);

static macro Expression $note.callable_target(Expr $target) =>
  $target ? %"target signature: $($target.repr())"
          : "target signature: unresolved";

static macro Expression $note.callable_source(Expr $source) =>
  $source ? %"source signature: $($source.repr())"
          : "source signature: unresolved";

static macro Expression $func_address(Expr $value) => &$value;

static macro Expression $func_size(Expr $value) => sizeof $value;

/* A value computed after its setup statements. */
static macro Expression $statement_value(Expr $value, Stmt @setup) =>
  ({ @setup $value; });

// func adapters

/* The argument readers of one adapter, with its `Func` and argument vector
   parameters read as expressions. */
static typedef struct FuncReaders {
  Compiler c;
  Type diagnostic_type;
  List value, reference, fn, argv;
} FuncReaders;

// func adapter bodies

/** Binds the file-static context type `name` with the field rows `fields`,
    for callable defers and function-pointer `Func` values. The complete
    typedef is bound at once, so each field keeps its member type. It binds
    at file scope whatever local scope is open.
*/
List Compiler.capture_environment(Compiler c, List name, List fields) {
  Block local = c.sym.close_local_scopes();
  defer c.sym.reopen_scopes(local);
  return c.bind_syntax(
    $!Unit{ static typedef struct $name { @fields } $name; },
    <unit>, NULL);
}

/** Adapts a direct native function argument when `FuncAdapter` is expected.
    A noncapturing lambda is lowered to its direct function designator. Other
    arguments must be resolved direct designators, possibly parenthesized,
    cast, or addressed; an indirect function-pointer value is rejected.
    A function already having the adapter's pointee type passes through,
    and new helpers are cached and queued with `Compiler.add_early`.
*/
List Compiler.maybe_adapt_func_arg(
  Compiler c, List argument, List expected_type) {
  if (!_is_func_adapter(c, expected_type)) return argument;
  argument = c.lower_lambda_expr(argument);
  Type arg_type = NULL, List payload = NULL;
  match (argument) {
    case %(expr ?type ?matched_payload): {
      arg_type = type;
      payload = matched_payload;
    }
    default: return argument;
  }
  if (_is_func_adapter(c, arg_type)) return argument;
  Type source_type = NULL, List source_binding = NULL;
  if (!_direct_func_source(arg_type, payload, 1, source_type, source_binding))
    $fail.callable_direct(c, expected_type, arg_type);
  if (_is_func_adapter_target(c, source_type)) return argument;
  List adapter = _direct_func_adapter(
    c, expected_type, source_binding, source_type);
  return _func_bound(expected_type, adapter);
}

/** Builds an adapter with `type`'s public signature that passes its own
    Func as the first argument of `target`, before the declared arguments.
    The target can read per-instance bindings with `Func.context`.
*/
List Compiler.context_func_adapter(Compiler c, Type type, List target) {
  List self = c.sym.introduce(c.fresh_name("func_binding"));
  return _build_func_adapter(
    c, %("Func"), type, target, self, NULL,
    $(_func_bound(%("Func"), self)));
}

/** Puts `setup` at the entry of a block or typed expression `body`. */
List Compiler.prepend_setup(Compiler c, List body, List setup) {
  if (!setup) return body;
  Macro shape = $statement_value;
  match (body) {
    case %(block *items):
      return %(block @setup @items);
    case %(!set ?expression (expr ?type ?)):
      return c.rebuild_expression(type, shape(expression, setup));
  }
  return body;
}

/** Returns `(SIGNATURE (STORAGE READ)...)` for an adapter of a `Var`
    function taking the lambda parameter rows `entries`: its Func
    signature as a cached `List`, and each argument as `_func_reads`
    reads it from `argv` of the Func `fn`.
*/
List Compiler.func_parameters(Compiler c, List entries, List fn, List argv) {
  List types = c.lambda_param_types(entries);
  Type adapter = c.sym.resolve_key(%("FuncAdapter"));
  List reads = entries ? _func_reads(c, adapter, types, fn, argv) : NULL;
  return cons(c.cache_literal_list(%((func $types) "Var")), reads);
}

/** Returns the canonical signature shared by native and meta Func adapters. */
List Compiler.func_signature(Compiler c, Type type) {
  List params = NULL, Type result = NULL;
  type.function_parts(params, result);
  Array declared = [];
  foreach (List parameter in params)
    declared.push(
      parameter.type().rest_container()
        ? parameter : parameter.type().declared());
  List parameter_types = params ? declared.list_free() : %((void));
  Type declared_result = result.declared();
  return %((func $parameter_types) @declared_result);
}

// callable adapter construction

static int _is_func_adapter(Compiler c, Type type) {
  if (!type) return 0;
  Type adapter = c.sym.resolve_key(%("FuncAdapter"));
  if (!adapter) return 0;
  return c.sym.resolve_key(type) == adapter;
}

/* A function already written in the adapter's own shape needs no wrapper:
   C converts the designator to a pointer at the call. */
static int _is_func_adapter_target(Compiler c, Type type) {
  if (!type) return 0;
  Type adapter = c.sym.resolve_key(%("FuncAdapter"));
  if (!adapter || !adapter.is_pointer()) return 0;
  Type pointee = adapter.dereference();
  return type.canonicalize() == pointee.canonicalize();
}

module List _direct_func_adapter(
  Compiler c, Type diagnostic_type, List source_binding, Type source_type) {
  Type key_type = source_type.canonicalize();
  List key = %(fadapt $source_binding $key_type), adapter = NULL;
  $adapter.memo(c, key, adapter) {
    List target = _func_bound(source_type, source_binding);
    adapter = _build_func_adapter(
      c, diagnostic_type, source_type, target, NULL, NULL, NULL);
  }
  return adapter;
}

module List _build_func_adapter(
  Compiler c, Type diagnostic_type, Type source_type,
  List target, List supplied_fn_binding, List prefix, List leading) {
  List params = NULL, Type return_type = NULL;
  source_type.function_parts(params, return_type);
  if (_typed_params_variadic(params)) {
    Type func_type = c.sym.resolve_key(%("Func"));
    $fail.callable_variadic(c, diagnostic_type, source_type, func_type);
  }
  /* Func.apply already packed the tail. Read and call its native container
     ABI. */
  if (params && params.last().type().rest_container()) {
    params = params.map(_native_parameter);
    Type native_type = target.cadr();
    List target_params = NULL, Type target_result = NULL;
    native_type.function_parts(target_params, target_result);
    target_params = target_params.map(_native_parameter);
    Type direct = %((func $target_params) @target_result);
    native_type = native_type.is_pointer() ? %(* @direct) : direct;
    target = %(expr $native_type $(target.caddr()));
  }
  source_type = source_type.canonicalize();
  return_type = return_type.canonicalize();

  _require_func_readers(c, diagnostic_type, source_type);

  String name = c.fresh_name("func_adapt");
  List adapter_binding = c.sym.introduce(name);
  List fn_binding = supplied_fn_binding
                  ? supplied_fn_binding
                  : c.sym.introduce(c.fresh_name("func_binding"));
  List argv_binding = c.sym.introduce(c.fresh_name("func_argv"));
  List names = _auto_names(c, params.len());
  List locals = _func_argument_locals(
    c, diagnostic_type, params, names, fn_binding, argv_binding);
  List arguments = params.zip_with(names, _func_bound);
  List call = _func_call(c, return_type, target, %(@leading @arguments));
  Type resolved_result = c.sym.resolve_key(return_type);
  if (resolved_result && resolved_result.car() == <struct>)
    call = _func_record_call(c, return_type, call);
  _publish_func_adapter(
    c, adapter_binding, fn_binding, argv_binding, call, %(@prefix @locals));
  return adapter_binding;
}

static void _require_func_readers(
  Compiler c, Type diagnostic_type, Type source_type) {
  foreach (String helper_name in
           %("x2c_func_value_argument"
             "x2c_func_declared_reference_argument")) {
    Type helper_type = NULL;
    List helper = _adapter_helper(c, helper_name, helper_type);
    if (!helper || !helper_type)
      $fail.callable_readers(c, diagnostic_type, source_type);
  }
}

/* Materialize arguments in index order: C does not sequence call operands,
   and a reader failure must prevent later conversions and body effects. */
static List _func_argument_locals(
  Compiler c, Type diagnostic_type, List types, List names,
  List fn_binding, List argv_binding) {
  List reads = _func_reads(
    c, diagnostic_type, types, $!Func{ $fn_binding },
    $!(const FuncArg *){ $argv_binding });
  Array locals = [];
  foreach (List read in reads) {
    (Type storage_type, List value) = read;
    List binding = names.car();
    names = names.cdr();
    locals.push(
      c.rebuild_statement($!{ $storage_type $binding = $value; }).cadr());
  }
  return locals.list_free();
}

/* Each argument of `types` read from `argv`, the argument vector of the
   Func `fn`, as `(STORAGE READ)`: the type of the local that holds it and
   the expression that reads it. */
static List _func_reads(
  Compiler c, Type diagnostic_type, List types, List fn, List argv) {
  Type value_type = NULL, reference_type = NULL;
  List value_helper = _adapter_helper(
    c, "x2c_func_value_argument", value_type);
  List reference_helper = _adapter_helper(
    c, "x2c_func_declared_reference_argument", reference_type);
  FuncReaders readers = {
    .c = c, .diagnostic_type = diagnostic_type,
    .value = _func_bound(value_type, value_helper),
    .reference = _func_bound(reference_type, reference_helper),
    .fn = fn, .argv = argv
  };
  Array reads = [], int index = 0;
  foreach (Type type in types) {
    Type storage_type = NULL;
    List value = _read(readers, type, index++, storage_type);
    reads.push($(storage_type, value));
  }
  return reads.list_free();
}

static List _read(
  FuncReaders &r, Type parameter_type, int index, Type &storage_type) {
  parameter_type = _native_parameter(parameter_type);
  if (parameter_type.is_reference())
    return _reference(r, parameter_type, index, storage_type);
  Symbol tag = r.c.sym.var_tag_for_type(parameter_type, NULL);
  Type resolved = r.c.sym.resolve_key(parameter_type);
  if (!tag && resolved &&
      (resolved.is_pointer() || resolved.car() == <struct>))
    return _pointer(r, parameter_type, resolved, index, storage_type);
  return _value(r, parameter_type, tag, index, storage_type);
}

/* A rest parameter reaches native code as its container. */
static Type _native_parameter(Type parameter) {
  Type container = parameter.rest_container();
  return container ? container : parameter;
}

static List _reference(
  FuncReaders &r, Type parameter_type, int index, Type &storage_type) {
  Compiler c = r.c;
  Type target = parameter_type.cdr(), pointer = target.reference();
  List picked = _call(
    r, $!Type{ void * }, r.reference, index,
    $(c.cache_literal_list(target), _type_literal(c, target)));
  storage_type = pointer;
  return c.convert_expression(picked, pointer);
}

static List _pointer(
  FuncReaders &r, Type parameter_type, Type resolved, int index,
  Type &storage_type) {
  Compiler c = r.c;
  /* A pointer without its own Var tag and a by-value record both arrive as
     `<p48>`; the latter is the address of the record's bytes. */
  Type pointer_type = NULL;
  List pointer_helper = _adapter_helper(
    c, "x2c_func_pointer_argument", pointer_type);
  List picked = _call(
    r, $!Type{ void * }, _func_bound(pointer_type, pointer_helper),
    index, NULL);
  storage_type = parameter_type;
  if (resolved.is_pointer())
    return c.convert_expression(picked, parameter_type);
  Type record_pointer = parameter_type.reference();
  List pointer = %(expr $record_pointer (cast $record_pointer $picked));
  return $!($parameter_type){ *$pointer };
}

static List _value(
  FuncReaders &r, Type parameter_type, Symbol tag, int index,
  Type &storage_type) {
  if (!tag)
    $fail.callable_parameter(r.c, r.diagnostic_type, parameter_type);
  List picked = _call(
    r, %("Var"), r.value, index, $(_adapter_symbol_literal(tag)));
  storage_type = parameter_type;
  return r.c.convert_expression(picked, parameter_type);
}

/* Call a resolved adapter reader without rebinding its typed arguments. */
static List _call(
  FuncReaders &r, Type result_type, List target, int index,
  List details) {
  List arguments = $(r.fn, r.argv, $!int{ $index }, @details);
  return _func_call(r.c, result_type, target, arguments);
}

/* One emitted FuncAdapter ABI. Callers order context setup around argument
   locals; the ordinary helper body owner boxes results and preserves
   no-value returns. */
static void _publish_func_adapter(
  Compiler c, List binding, List fn_binding, List argv_binding,
  List body, List setup) {
  List fn_parameter = Type.parameter_ast(%("Func"), fn_binding);
  List argv_parameter = Type.parameter_ast(%(* const "FuncArg"), argv_binding);
  c.add_early(
    c.wrapper_function(
      %(static "Var"), binding, $(fn_parameter, argv_parameter),
      c.prepend_setup(_helper_body(c, body), setup).cdr()));
}

/* The body of an adapter that runs `body`: a block's items and then a
   return of no value, a void expression and then that return, or a return
   of the expression's value as a `Var`. */
static List _helper_body(Compiler c, List body) {
  match (body) {
    case %(block *items):
      return %(block @items $(Ast.return_none()));
    case %(expr (void) ?):
      return %(block (stmnt $body) $(Ast.return_none()));
  }
  List result = c.convert_expression(body, %("Var"));
  return %(block (stmnt (return $result)));
}

static List _func_record_call(Compiler c, Type return_type, List call) {
  /* A record result is returned as `<p48>` to a copy of its bytes. */
  Type result_type = NULL;
  List result_helper = _adapter_helper(
    c, "x2c_func_record_result", result_type);
  List result = c.sym.introduce(c.fresh_name("func_record"));
  List value = _func_bound(return_type, result);
  Macro address_shape = $func_address, size_shape = $func_size;
  List address = c.rebuild_expression(
    return_type.reference(), address_shape(value));
  List size = c.rebuild_expression(%(unsigned long), size_shape(value));
  List helper = _func_bound(result_type, result_helper);
  List boxed = _func_call(c, %("Var"), helper, $(address, size));
  return c.rebuild_statement(
    $!{ { $return_type $result = $call; return $boxed; } }).cadr();
}

static List _type_literal(Compiler c, Type type) =>
  c.cache_literal_list(c.sym.normalize_declared_type(type));

static List _adapter_symbol_literal(Symbol value) =>
  %(expr ("Symbol") "$((unsigned long) value)");

module List _adapter_helper(Compiler c, String name, Type &type) =>
  c.sym.resolve_global($(name), type);

/* The issued identity `binding` read as a `type`. */
module List _func_bound(Type type, List binding) => $!($type){ $binding };

module List _func_call(Compiler c, Type type, List callee, List arguments) {
  Macro shape = $called;
  return c.rebuild_expression(type, shape(callee, arguments));
}

// Each a0..aN name gets a fresh binding identity.
static List _auto_names(Compiler c, int count) {
  Array out = [];
  for (int index = 0; index < count; index++)
    out.push(c.sym.introduce(%"a$index"));
  return out.list_free();
}

module int _typed_params_variadic(List params) {
  foreach (Var value in params) {
    if (value == <...> || (value ~= %(...))) return 1;
  }
  return 0;
}

module void _adapter_error(
  Compiler c, String message, Type target, Type source, List details) {
  String target_note = $note.callable_target(target);
  String source_note = $note.callable_source(source);
  c.report_error(<type>, message, NULL, $(target_note, source_note, @details));
}
