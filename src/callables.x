/*  callables.x -- callable values lowered to C helpers

    Copyright (c) 2026 Gary William Flake.

    A callable value that C cannot spell directly becomes a static helper
    queued with `Compiler.add_early`. Every `Func` helper shares one
    `FuncAdapter` ABI: arguments are read in index order from the argument
    vector, and the result is boxed into a `Var`. `src/component-lambdas.x`
    lowers lambdas.
*/

#pragma once
#include "compiler.x"

#include "adapter-memo.x"
#include "ast-rewrite.x"
#include "meta.x"
#include "grammar.x"

/* Callable conversion failures retain the shared signature-note owner. */

static macro Stmt $report.callable.shared(Expr $c, Expr $source) =>
  _adapter_error(
    $c, "function conversion needs x2c_func_shared from lib/func.x",
    %("Func"), $source, NULL);

static macro Stmt $report.callable.context(Expr $c, Expr $source) =>
  _adapter_error(
    $c, "function pointer conversion needs Func.new_context from lib/func.x",
    %("Func"), $source, NULL);

static macro Stmt $report.callable.native_context(
  Expr $c, Expr $target, Expr $source) =>
  _adapter_error(
    $c, "native binding needs Func.context from lib/func.x",
    $target, $source, NULL);

static macro Stmt $report.callable.direct(
  Expr $c, Expr $target, Expr $source) =>
  _adapter_error(
    $c, "native binding target must be a direct function",
    $target, $source,
    %("supported: a free function or Type.method designator"));

static macro Stmt $report.callable.variadic(
  Expr $c, Expr $target, Expr $source, Expr $func_type) {
  String message = $c.sym.resolve_key($target) == $func_type
    ? "function conversion to Func cannot be variadic"
    : "native binding target cannot be variadic";
  _adapter_error($c, message, $target, $source, NULL);
}

static macro Stmt $report.callable.readers(
  Expr $c, Expr $target, Expr $source) =>
  _adapter_error(
    $c, "native binding needs Func argument readers from lib/func.x",
    $target, $source, NULL);

static macro Stmt $report.callable.parameter(
  Expr $c, Expr $target, Expr $source) =>
  _adapter_error(
    $c, "native binding parameter type has no Var representation",
    $target, $source, NULL);

static macro Stmt $report.callback.direct(Expr $cb) =>
  _fail(
    $cb, "typed callback adapter source must be a direct function",
    %("supported: a free function or Type.method designator"));

static macro Stmt $report.callback.target(Expr $cb) =>
  _fail($cb, "typed callback adapter target is incomplete", NULL);

static macro Stmt $report.callback.source(Expr $cb) =>
  _fail($cb, "typed callback adapter source is incomplete", NULL);

static macro Stmt $report.callback.variadic(Expr $cb) =>
  _fail($cb, "typed callback adapter cannot be variadic", NULL);

static macro Stmt $report.callback.arity(
  Expr $cb, Expr $target_count, Expr $source_count) {
  String detail = "target has %d parameters; source has %d".printf(
    $target_count, $source_count);
  _fail($cb, "typed callback adapter arity mismatch", %($detail));
}

static macro Stmt $report.callback.void_return(Expr $cb) =>
  _fail($cb, "typed callback adapter does not support void return", NULL);

static macro Stmt $report.callback.result(Expr $cb) =>
  _fail($cb, "typed callback adapter return type mismatch", NULL);

static macro Stmt $report.callback.parameter(
  Expr $cb, Expr $index, Expr $target, Expr $source) {
  String detail = "parameter %d: %s cannot adapt to %s".printf(
    $index + 1, $target.repr(), $source.repr());
  _fail($cb, "typed callback adapter parameter mismatch", %($detail));
}

static macro Expression $callable.note.target(Expr $target) =>
  $target ? %"target signature: ${$target.repr()}"
          : "target signature: unresolved";

static macro Expression $callable.note.source(Expr $source) =>
  $source ? %"source signature: ${$source.repr()}"
          : "source signature: unresolved";

#include "ast.x"
#include "type.x"
#include "parse.x"
#include "expressions.x"
#include "protocol.x"
#include "transform.x"
#include "lambdas.x"

/* Helper syntax shared by every lowering below. */

static macro Expression $func_address(Expr $value) => &$value;

static macro Expression $func_size(Expr $value) => sizeof $value;

// Func adapter bodies

/* The body of an adapter that runs `body`: a block's items and then a
   return of no value, a void expression and then that return, or a return
   of the expression's value as a `Var`. */
static List _helper_body(Compiler c, List body) {
  match (body) {
    case $source_block_content(%(*items)):
      return source_block_content(%(@items ${source_return_none()}));
    case %(expr (void) ?):
      return source_block_content(
        %((stmnt $body) ${source_return_none()}));
  }
  List result = c.convert_expression(body, %("Var"));
  return source_block_content(%((stmnt (return $result))));
}

/** Binds the file-static context type `name` with the field rows `fields`,
    for callable defers. The complete typedef is bound at once, so each
    field keeps its member type.
*/
List Compiler.capture_environment(Compiler c, List name, List fields) {
  return c.bind_syntax(
    $!Unit{ static typedef struct $name { @fields } $name; },
    AST_UNIT, NULL);
}

/* A value computed after its setup statements. */
static macro Expression $statement_value(Expr $value, Stmt @setup) =>
  ({ @setup $value; });

/** Puts `setup` at the entry of a block or typed expression `body`. */
List Compiler.prepend_setup(Compiler c, List body, List setup) {
  if (!setup) return body;
  Macro shape = $statement_value;
  match (body) {
    case $source_block_content(%(*items)):
      return source_block_content(%(@setup @items));
    case %(!set ?expression (expr ?type ?)):
      return c.rebuild_expression(type, shape(expression, setup));
  }
  return body;
}

// Func values

/** Converts a resolved function-like expression to `Func` when supported.
    Existing `Func` values pass through. Direct fixed functions reuse a
    file-static handle; other function-typed and function-pointer expressions
    are evaluated once and copied into a new context-bound `Func`, with null
    pointers producing null `Func`. Lambda expressions are lowered first, and
    unrelated expressions pass through unchanged. Public inline functions
    reach the queued helpers through generated bridge functions.
*/
List Compiler.lift_func_expression(Compiler c, List expression) {
  Type type = NULL;
  List payload = NULL;
  match (expression)
    case %(expr ?matched_type ?matched_payload): {
      type = matched_type;
      payload = matched_payload;
    }
  if (!type) return _deref_func_lift(c, expression, payload);
  Type func_type = c.sym.resolve_key(%("Func"));
  if (c.sym.resolve_key(type) == func_type) return expression;

  match (expression)
    case $lambda_expression(?body, *params): {
      expression = c.lower_lambda_expr(expression);
      match (expression)
        case %(expr ?lowered_type ?lowered_payload): {
          type = lowered_type;
          payload = lowered_payload;
        }
      if (c.sym.resolve_key(type) == func_type) return expression;
    }

  Type source_type = NULL;
  List source_binding = NULL;
  if (_direct_func_source(type, payload, 0, source_type, source_binding))
    return _direct_func_value(c, source_binding, source_type);

  Type pointer_type = _func_pointer_value_type(c, type);
  if (pointer_type) return _indirect_func_lift(c, expression, pointer_type);
  Type resolved = c.sym.resolve_key(type);
  if (resolved && resolved.is_function()) {
    Type pointer = cons(<*>, resolved);
    return _indirect_func_lift(c, %(expr $pointer $payload), pointer);
  }
  return _deref_func_lift(c, expression, payload);
}

/* The direct function a designator names under parentheses and address-of,
   and under casts when `through_cast` is set. */
static int _direct_func_source(
  Type type, List payload, int through_cast, Type &source_type,
  List &source_binding) {
  match (payload) {
    case $source_identifier_content(%(?binding)): {
      if (!type || type.is_pointer() || !type.is_function()) return 0;
      source_type = type;
      source_binding = binding;
      return 1;
    }
    case $source_cast_content(%(? (expr ?inner_type ?inner_payload))):
      return through_cast && _direct_func_source(
        inner_type, inner_payload, 1, source_type, source_binding);
    case $source_content_pattern($grouped, %(?inner)):
      match (inner)
        case %(expr ?inner_type ?inner_payload):
          return _direct_func_source(
            inner_type, inner_payload, through_cast, source_type,
            source_binding);
    case $source_operator_content(%(& (expr ?inner_type ?inner_payload))):
      return _direct_func_source(
        inner_type, inner_payload, through_cast, source_type,
        source_binding);
  }
  return 0;
}

static List _direct_func_value(
  Compiler c, List source_binding, Type source_type) {
  List handle = _direct_func_handle(c, source_binding, source_type);
  if (!c.inline_header) return handle;

  Type key_type = source_type.canonicalize();
  List key = %(fgetter $source_binding $key_type);
  List bridge = NULL;
  List parameters = %(params (param (void) (bind () ())));
  $adapter.memo(c, key, bridge) {
    bridge = _func_bridge_binding(c, "func_get");
    c.add_early(
      c.wrapper_function(
        %("Func"), bridge, parameters.cdr(),
        _func_return_body(c, handle)));
  }
  Type getter_type = $!Type{ Func (void) };
  return _func_bridge_call(c, bridge, parameters, getter_type, NULL);
}

static List _direct_func_handle(
  Compiler c, List source_binding, Type source_type) {
  Type key_type = source_type.canonicalize();
  List key = %(fhandle $source_binding $key_type);
  List handle = NULL;
  $adapter.memo(c, key, handle) {
    List adapter = _direct_func_adapter(
      c, %("Func"), source_binding, source_type);
    List signature = _func_signature_literal(c, source_type);
    Type constructor_type = NULL;
    List constructor = _adapter_helper(
      c, "x2c_func_shared", constructor_type);
    if (!constructor || !constructor_type)
      $report.callable.shared(c, source_type);
    handle = c.sym.introduce(c.fresh_name("func_handle"));
    List value = _func_call(
      c, %("Func"), _func_bound(constructor_type, constructor),
      %(${_func_bound(%("FuncAdapter"), adapter)} $signature));
    c.add_early(
      c.rebuild_statement($!{ static Func $handle = $value; }).cadr());
  }
  return _func_bound(%("Func"), handle);
}

static List _func_bridge_binding(Compiler c, String stem) {
  String hash = "%08x".printf(c.filename.hash());
  return c.sym.introduce(c.fresh_name(%"${stem}_$hash"));
}

static List _func_bridge_call(
  Compiler c, List bridge, List parameters,
  Type function_type, List arguments) {
  List call = _func_call(
    c, %("Func"), _func_bound(function_type, bridge), arguments);
  /* A call through a bridge function the unit declares where it calls. */
  return $!Func{ ({
    extern Func $bridge(@{parameters.cdr()});
    $call;
  }) };
}

static Type _func_pointer_value_type(Compiler c, Type type) {
  Type resolved = c.sym.resolve_key(type);
  if (resolved) type = resolved;
  while (type && _func_type_qualifier(type.car())) type = type.cdr();
  if (!type || type.car() != <*>) return NULL;
  List tail = type.cdr();
  while (tail && _func_type_qualifier(tail.car())) tail = tail.cdr();
  Type pointer = cons(<*>, tail);
  return pointer.dereference().is_function() ? pointer : NULL;
}

static int _func_type_qualifier(Var value) =>
  value == <const> || value == <volatile> || value == <restrict>;

static List _indirect_func_lift(
  Compiler c, List expression, Type pointer_type) {
  if (!c.inline_header)
    return _indirect_func_value(c, expression, pointer_type);

  Type key_type = pointer_type.canonicalize();
  List key = %(fpointer-factory $key_type);
  List bridge = NULL;
  $adapter.memo(c, key, bridge) {
    bridge = _func_bridge_binding(c, "func_from_pointer");
    List parameter = c.sym.introduce(c.fresh_name("func_pointer"));
    List parameters = %(
      params ${pointer_type.parameter_ast(parameter)}
    );
    List value = _indirect_func_value(
      c, _func_bound(pointer_type, parameter), pointer_type);
    c.add_early(
      c.wrapper_function(
        %("Func"), bridge, parameters.cdr(),
        _func_return_body(c, value)));
  }
  List parameters = %(
    params ${pointer_type.parameter_ast(NULL)}
  );
  Type factory_type = %((func ($pointer_type)) "Func");
  return _func_bridge_call(
    c, bridge, parameters, factory_type, %($expression));
}

static List _indirect_func_value(
  Compiler c, List expression, Type pointer_type) {
  Type context_type = NULL;
  List context_field = NULL;
  List adapter = _indirect_func_adapter(
    c, %("Func"), pointer_type, context_type, context_field);
  List signature = _func_signature_literal(c, pointer_type);
  Type constructor_type = NULL;
  List constructor = _adapter_helper(c, "Func_new_context", constructor_type);
  if (!constructor || !constructor_type)
    $report.callable.context(c, pointer_type);

  List context = c.sym.introduce(c.fresh_name("func_pointer_context"));
  List declaration = _func_context_declaration(
    c, context_type, context, expression);
  String field_name = Ast.binding_spelling(context_field);
  List pointer = %(
    expr $pointer_type
      (op . ${_func_bound(context_type, context)} ($field_name)));
  List constructed = _func_context_call(
    c, context_type, context, _func_bound(%("FuncAdapter"), adapter),
    signature, _func_bound(constructor_type, constructor));
  return $!Func{ ({
    $declaration ${_func_present_statement(c, pointer, constructed)}
  }) };
}

static List _indirect_func_adapter(
  Compiler c, Type diagnostic_type, Type pointer_type,
  Type &out_context_type, List &out_context_field) {
  List key = %(findirect $pointer_type), result = NULL;
  $adapter.memo(c, key, result) {
    result = _build_indirect_func_adapter(c, diagnostic_type, pointer_type);
  }
  (List adapter, Type context, List field) = result.cdr();
  out_context_type = context;
  out_context_field = field;
  return adapter;
}

static List _build_indirect_func_adapter(
  Compiler c, Type diagnostic_type, Type pointer_type) {
  String context_name = NULL;
  List field_binding = NULL;
  _func_pointer_context(c, pointer_type, context_name, field_binding);
  Type context_type = %($context_name);
  Type context_pointer = %(* const $context_name);
  Type context_helper_type = NULL;
  if (!_adapter_helper(c, "Func_context", context_helper_type) ||
      !context_helper_type)
    $report.callable.native_context(c, diagnostic_type, pointer_type);
  List fn_binding = c.sym.introduce(c.fresh_name("func_binding"));
  List context_local = c.sym.introduce(c.fresh_name("func_pointer_context"));
  List context_declaration = _context_local(
    c, context_type, context_local, fn_binding);
  String field_name = Ast.binding_spelling(field_binding);
  List context = _func_bound(context_pointer, context_local);
  List target = $!($pointer_type){ $context->$field_name };
  List adapter = _build_func_adapter(
    c, diagnostic_type, pointer_type, target, fn_binding,
    %($context_declaration), NULL);
  return %(indirect-adapter $adapter $context_type $field_binding);
}

/* Inside an adapter, `local` points at the context `fn` copied, typed as a
   `value_type` record. */
static List _context_local(
  Compiler c, Type value_type, List local, List fn) {
  Type pointer = $!Type{ const $value_type * };
  Type helper_type = NULL;
  List helper = _adapter_helper(c, "Func_context", helper_type);
  List call = _func_call(
    c, $!Type{ const void * }, _func_bound(helper_type, helper),
    %(${_func_bound(%("Func"), fn)}));
  List cast = %(expr $pointer (cast $pointer $call));
  return c.rebuild_statement($!{ $pointer $local = $cast; }).cadr();
}

static void _func_pointer_context(
  Compiler c, Type pointer_type, String &context_name,
  List &field_binding) {
  context_name = c.fresh_name("func_pointer_context");
  List context_binding = c.sym.introduce(context_name);
  field_binding = c.sym.introduce(c.fresh_name("func_pointer"));
  List (field_base, field_mods) = pointer_type.parts();
  c.add_early(
    %(
    typedef
      (static struct $context_name
        (fields
          (declare $field_base
            (bindings (bind $field_binding $field_mods)))))
      (bindings (bind $context_binding ()))
  ));
}

static List _func_context_declaration(
  Compiler c, Type context_type, List context, List expression) {
  List value = $!($context_type){ { $expression } };
  return c.rebuild_statement($!{ $context_type $context = $value; }).cadr();
}

/* `Func.new_context(adapter, signature, &context, sizeof context)`, with
   the adapter and constructor already typed. */
static List _func_context_call(
  Compiler c, Type type, List context, List adapter, List signature,
  List constructor) {
  List value = _func_bound(type, context);
  Macro address_shape = $func_address, size_shape = $func_size;
  List address = c.rebuild_expression(type.reference(), address_shape(value));
  List size = c.rebuild_expression(%(size_t), size_shape(value));
  return _func_call(
    c, %("Func"), constructor, %($adapter $signature $address $size));
}

static List _func_present_statement(
  Compiler c, List pointer, List constructed) {
  List null_binding = c.sym.reference(%("NULL"), NULL);
  List result = $!Func{
    $pointer ? $constructed : ${_func_bound(%("Func"), null_binding)} };
  return c.rebuild_statement($!{ $result; }).cadr();
}

/* A dereferenced function pointer reaches the lift untyped or typed as a
   bare pointer, possibly under parens or address-of shells; recover the
   callable type from the pointer operand. Unsupported shapes pass through. */
static List _deref_func_lift(
  Compiler c, List expression, List payload) {
  List probe = payload;
  int unwrapped = 1;
  while (unwrapped) {
    unwrapped = 0;
    match (probe) {
      case $source_content_pattern($grouped, %(?inner)):
        match (inner)
          case %(expr ? ?inner_payload): {
            probe = inner_payload;
            unwrapped = 1;
          }
      case $source_operator_content(%(& (expr ? ?inner_payload))): {
        probe = inner_payload;
        unwrapped = 1;
      }
    }
  }
  match (probe)
    case $source_operator_content(%(* (expr ?operand_type ?))): {
      Type resolved = c.sym.resolve_key(operand_type);
      if (resolved && resolved.is_pointer() &&
          resolved.dereference().is_function())
        return _indirect_func_lift(c, %(expr $resolved $payload), resolved);
    }
  return expression;
}

// Func adapters

/* The argument readers of one adapter, with its `Func` and argument vector
   parameters read as expressions. */
static typedef struct FuncReaders {
  Compiler c;
  Type diagnostic_type;
  List value, reference, fn, argv;
} FuncReaders;

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
    $report.callable.direct(c, expected_type, arg_type);
  if (_is_func_adapter_target(c, source_type)) return argument;
  List adapter = _direct_func_adapter(
    c, expected_type, source_binding, source_type);
  return _func_bound(expected_type, adapter);
}

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

static List _direct_func_adapter(
  Compiler c, Type diagnostic_type, List source_binding, Type source_type) {
  Type key_type = source_type.canonicalize();
  List key = %(fadapt $source_binding $key_type);
  List adapter = NULL;
  $adapter.memo(c, key, adapter) {
    List target = _func_bound(source_type, source_binding);
    adapter = _build_func_adapter(
      c, diagnostic_type, source_type, target, NULL, NULL, NULL);
  }
  return adapter;
}

static List _build_func_adapter(
  Compiler c, Type diagnostic_type, Type source_type,
  List target, List supplied_fn_binding, List prefix, List leading) {
  List params = NULL, Type return_type = NULL;
  source_type.function_parts(params, return_type);
  if (_typed_params_variadic(params)) {
    Type func_type = c.sym.resolve_key(%("Func"));
    $report.callable.variadic(c, diagnostic_type, source_type, func_type);
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
  List arguments = params.zip_with(
    names, _func_bound);
  List call = _func_call(c, return_type, target, %(@leading @arguments));
  Type resolved_result = c.sym.resolve_key(return_type);
  if (resolved_result && resolved_result.car() == <struct>)
    call = _func_record_call(c, return_type, call);
  _publish_func_adapter(
    c, adapter_binding, fn_binding, argv_binding, call, %(@prefix @locals));
  return adapter_binding;
}

/** Builds an adapter with `type`'s public signature that passes its own
    Func as the first argument of `target`, before the declared arguments.
    The target can read per-instance bindings with `Func.context`. */
List Compiler.context_func_adapter(Compiler c, Type type, List target) {
  List self = c.sym.introduce(c.fresh_name("func_binding"));
  return _build_func_adapter(
    c, %("Func"), type, target, self, NULL,
    %(${_func_bound(%("Func"), self)}));
}

static void _require_func_readers(
  Compiler c, Type diagnostic_type, Type source_type) {
  foreach (String helper_name,
           %("x2c_func_value_argument"
             "x2c_func_declared_reference_argument")) {
    Type helper_type = NULL;
    List helper = _adapter_helper(c, helper_name, helper_type);
    if (!helper || !helper_type)
      $report.callable.readers(c, diagnostic_type, source_type);
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
  foreach (List read, reads) {
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
  List value_helper = _adapter_helper(c, "x2c_func_value_argument", value_type);
  List reference_helper = _adapter_helper(
    c, "x2c_func_declared_reference_argument", reference_type);
  FuncReaders readers = {
    .c = c, .diagnostic_type = diagnostic_type,
    .value = _func_bound(value_type, value_helper),
    .reference = _func_bound(reference_type, reference_helper),
    .fn = fn, .argv = argv
  };
  Array reads = [];
  int index = 0;
  foreach (Type type, types) {
    Type storage_type = NULL;
    List value = _read(readers, type, index++, storage_type);
    reads.push(%($storage_type $value));
  }
  return reads.list_free();
}

/** Returns `(SIGNATURE (STORAGE READ)...)` for an adapter of a `Var`
    function taking the lambda parameter rows `entries`: its Func
    signature as a cached `List`, and each argument as `_func_reads`
    reads it from `argv` of the Func `fn`. */
List Compiler.func_parameters(
  Compiler c, List entries, List fn, List argv) {
  List types = c.lambda_param_types(entries);
  Type adapter = c.sym.resolve_key(%("FuncAdapter"));
  List reads = entries ? _func_reads(c, adapter, types, fn, argv) : NULL;
  return cons(c.cache_literal_list(%((func $types) "Var")), reads);
}

static List _read(
  FuncReaders &r, Type parameter_type, int index, Type &storage_type) {
  if (parameter_type.is_reference())
    return _reference(r, parameter_type, index, storage_type);
  Symbol tag = r.c.sym.var_tag_for_type(parameter_type, NULL);
  Type resolved = r.c.sym.resolve_key(parameter_type);
  if (!tag && resolved &&
      (resolved.is_pointer() || resolved.car() == <struct>))
    return _pointer(r, parameter_type, resolved, index, storage_type);
  return _value(r, parameter_type, tag, index, storage_type);
}

static List _reference(
  FuncReaders &r, Type parameter_type, int index, Type &storage_type) {
  Compiler c = r.c;
  Type target = parameter_type.cdr(), pointer = target.reference();
  List picked = _call(
    r, $!Type{ void * }, r.reference, index,
    %(${c.cache_literal_list(target)} ${_type_literal(c, target)}));
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
    r,
    $!Type{ void * }, _func_bound(pointer_type, pointer_helper), index, NULL);
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
    $report.callable.parameter(r.c, r.diagnostic_type, parameter_type);
  List picked = _call(
    r, %("Var"), r.value, index, %(${_adapter_symbol_literal(tag)}));
  storage_type = parameter_type;
  return r.c.convert_expression(picked, parameter_type);
}

/* Call a resolved adapter reader without rebinding its typed arguments. */
static List _call(
  FuncReaders &r, Type result_type, List target, int index,
  List details) {
  List arguments = %(${r.fn} ${r.argv} ${$!int{ $index }} @details);
  return _func_call(r.c, result_type, target, arguments);
}

/* One emitted FuncAdapter ABI. Callers order context setup around argument
   locals; the ordinary helper body owner boxes results and preserves
   no-value returns. */
static void _publish_func_adapter(
  Compiler c, List binding, List fn_binding, List argv_binding,
  List body, List setup) {
  List parameters = _named_decl_params(
    %(("Func") (* const "FuncArg")), %($fn_binding $argv_binding));
  c.add_early(
    c.wrapper_function(
      %(static "Var"), binding, parameters.cdr(),
      c.prepend_setup(_helper_body(c, body), setup).cdr()));
}

static List _func_record_call(
  Compiler c, Type return_type, List call) {
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
  List boxed = _func_call(c, %("Var"), helper, %($address $size));
  /* The record is copied into a Var after the native call completes. */
  return c.rebuild_statement(
    $!{ { $return_type $result = $call; return $boxed; } }).cadr();
}

/** Returns the canonical signature shared by native and meta Func adapters. */
List Compiler.func_signature(Compiler c, Type type) {
  List params = NULL;
  Type result = NULL;
  type.function_parts(params, result);
  Array declared = [];
  foreach (List parameter, params) declared.push(parameter.type().declared());
  List parameter_types = params ? declared.list_free() : %((void));
  Type declared_result = result.declared();
  return %((func $parameter_types) @declared_result);
}

static List _func_signature_literal(Compiler c, Type type) =>
  c.cache_literal_list(c.func_signature(type));

static List _type_literal(Compiler c, Type type) =>
  c.cache_literal_list(c.sym.normalize_declared_type(type));

static List _adapter_symbol_literal(Symbol value) =>
  %(expr ("Symbol") "${(unsigned long) value}");

static List _adapter_helper(Compiler c, String name, Type &type) =>
  c.sym.resolve_global(%($name), type);

/* The issued identity `binding` read as a `type`. */
static List _func_bound(Type type, List binding) => $!($type){ $binding };

static List _func_call(
  Compiler c, Type type, List callee, List arguments) {
  Macro shape = $called;
  return c.rebuild_expression(type, shape(callee, arguments));
}

static List _func_return_body(Compiler c, List value) {
  Macro shape = $return_value;
  return c.rebuild_statement(shape(value)).cdr();
}

// Build fresh binding identities a0..aN.
static List _auto_names(Compiler c, int count) {
  Array out = [];
  for (int index = 0; index < count; index++)
    out.push(c.sym.introduce(%"a$index"));
  return out.list_free();
}

// Produce typed parameters from types and their binding identities.
static List _named_decl_params(List types, List names) {
  List params = types.zip_with(
    names, %!(Type type, List name) => type.parameter_ast(name));
  return %(params @params);
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
      $let(c.origin, at) {
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
    $report.callback.direct(c);
  if (!c.target.function_parts(c.params, c.result))
    $report.callback.target(c);
  if (!source.function_parts(c.source_params, c.source_result))
    $report.callback.source(c);
  if (_typed_params_variadic(c.params) ||
      _typed_params_variadic(c.source_params))
    $report.callback.variadic(c);
}

static void _check_signature(Callback &cb) {
  int target_count = cb.params.len(), source_count = cb.source_params.len();
  // lint: allow one-statement-braces ST-1: macro emits declaration and call
  if (target_count != source_count) {
    $report.callback.arity(cb, target_count, source_count);
  }
  cb.result = cb.result.canonicalize();
  cb.source_result = cb.source_result.canonicalize();
  if (cb.result === %(void) || cb.source_result === %(void))
    $report.callback.void_return(cb);
  if (cb.result != cb.source_result)
    $report.callback.result(cb);
}

static void _check_params(Callback &cb) {
  int index = 0;
  List targets = cb.params, sources = cb.source_params;
  for (; targets;
       targets = targets.cdr(), sources = sources.cdr(), index++) {
    Type target = targets.car();
    Type source = sources.car();
    if (_allows(cb, target, source)) continue;
    $report.callback.parameter(cb, index, target, source);
  }
}

// Permit matching parameter types and one dynamic extraction.
static int _allows(Callback &cb, Type target, Type source) {
  target = target.canonicalize();
  source = source.canonicalize();
  if (target == source) return 1;
  with cb.c.sym {
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
  foreach(Var entry, raw_params) {
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

static int _typed_params_variadic(List params) {
  foreach(Var value, params) {
    if (value == <...>) return 1;
    match (value) case %(...): return 1;
  }
  return 0;
}

static void _adapter_error(
  Compiler c, String message, Type target, Type source, List details) {
  String target_note = $callable.note.target(target);
  String source_note = $callable.note.source(source);
  c.report_error(<type>, message, NULL, %($target_note $source_note @details));
}
