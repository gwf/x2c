#pragma once

$(import "../lib/error-macros.xmacro")
#include "compiler.x"
#pragma private

$(import "../src/ast-rewrite.xmacro")
$(import "../src/adapter-memo.xmacro")
#include "meta.x"
$(import "../src/grammar.xmacro")

#include "ast.x"
#include "type.x"
#include "parse.x"
#include "expressions.x"
#include "string.x"
#include "symbol.x"
#include "var.x"
#include "list.x"
#include "protocol.x"
#include "transform.x"

// Produce typed parameters from types and their binding identities.
static List _named_decl_params(List types, List names) {
  List params = types.zip_with(
    names,
    %!(Type type, List name) => type.parameter_ast(name));
  return %(params @params);
}

// Build fresh binding identities a0..aN.
static List _auto_names(Compiler compiler, int count) {
  Array out = [];
  for (int index = 0; index < count; index++) {
    String pname = %"a$index";
    out.push(compiler.sym.introduce(pname));
  }
  return out.list_free();
}

// Preserve typed declarators; bare lambda parameters remain Var.
static List _params_to_decl_params(List names) {
  if (!names) return %(params (param (void) (bind () ()))) ;
  Array out = [];
  foreach(Var item, names)
    match (item) {
      case %(!set ?identity (binding ? ?)):
        out.push(%(param ("Var") (bind $identity ())));
      case %(param ? ?): out.push(item);
    }
  List params = out.list_free();
  return %(params @params);
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
  List result = types.list_free();
  out_types = result;
  return all_var;
}

// Split a direct or pointer function Type into fixed parameters and return.
static int _typed_function_parts(Type type, List &params, Type &?return_type) {
  if (!type) return 0;
  type = type.canonicalize();
  if (type.is_pointer()) type = type.dereference();
  match (type)
    case %((func (*parameters)) ?return_head *return_tail): {
      List values = parameters;
      match (values)
        case %(?(Type only)) if (only.canonicalize() === %(void)):
          values = NULL;
      params = values;
      if (return_type) return_type = %($return_head @return_tail);
      return 1;
    }
  return 0;
}

static int _typed_params_variadic(List params) {
  foreach(Var value, params) {
    if (value == <...>) return 1;
    match (value) case %(...): return 1;
  }
  return 0;
}

static void _typed_adapter_error(
  Compiler compiler, String message, Type target, Type source, List details) {
  String target_note = target
    ? %"target signature: ${target.repr()}"
    : "target signature: unresolved";
  String source_note = source
    ? %"source signature: ${source.repr()}"
    : "source signature: unresolved";
  compiler.report_error(
    <type>, message, NULL,
    %($target_note $source_note @details));
}

// Permit matching parameter types and one dynamic extraction.
static int _typed_param_allowed(Compiler compiler, Type target, Type source) {
  target = target.canonicalize();
  source = source.canonicalize();
  if (target == source) return 1;
  with compiler.sym {
    if (_.is_var_type(target) && _.is_var_type(source)) return 1;
    if (!_.is_var_type(target)) return 0;
    if (_.is_named_value_type(source, "Symbol")) return 1;
    return _.resolve_key(source).is_pointer();
  }
}

typedef struct CallbackBuild {
  Compiler compiler;
  List binding, parameters, source_binding, source_parameters;
  Type result, source_type;
} CallbackBuild;

static List _callback_function(CallbackBuild *build) {
  Compiler compiler = build.compiler;
  List parameters = build.parameters;
  Type result = build.result;
  Type source_type = build.source_type;
  List source_parameters = build.source_parameters;
  List names = _auto_names(compiler, parameters.len());
  List declaration_params = _named_decl_params(parameters, names);
  Array arguments = [];
  for (; parameters;
       parameters = parameters.cdr(),
       source_parameters = source_parameters.cdr(),
       names = names.cdr()) {
    List argument = %(expr ${parameters.car()} (ident ${names.car()}));
    arguments.push(
      compiler.convert_expression(argument, source_parameters.car()));
  }
  List source_binding = build.source_binding;
  List source = %(expr $source_type (ident $source_binding));
  List call = _func_call(
    compiler, source_type.apply().canonicalize(),
    source, arguments.list_free());
  Macro returned = $return_value;
  List statement = result === %(void) ? call
    : compiler.rebuild_statement(
      returned(compiler.convert_expression(call, result))).cadr();
  return compiler.wrapper_function(
    %(static @result), build.binding, declaration_params.cdr(),
    %((stmnt $statement)));
}

typedef struct TypedAdapter {
  Compiler compiler;
  Type target, source, target_return, source_return;
  List target_params, source_params, source_binding;
} TypedAdapter;

static void _typed_adapter_parts(TypedAdapter *adapter) {
  Compiler c = adapter.compiler;
  Type target = adapter.target, source = adapter.source;
  if (!adapter.source_binding || !source || source.is_pointer() ||
      !source.is_function())
    _typed_adapter_error(
      c, "typed callback adapter source must be a direct function",
      target, source,
      %("supported: a free function or Type.method designator"));
  if (!_typed_function_parts(
    target, adapter.target_params, adapter.target_return))
    _typed_adapter_error(
      c, "typed callback adapter target is incomplete", target, source, NULL);
  if (!_typed_function_parts(
    source, adapter.source_params, adapter.source_return))
    _typed_adapter_error(
      c, "typed callback adapter source is incomplete", target, source, NULL);
  if (_typed_params_variadic(adapter.target_params) ||
      _typed_params_variadic(adapter.source_params))
    _typed_adapter_error(
      c, "typed callback adapter cannot be variadic", target, source, NULL);
}

static void _typed_adapter_signature(TypedAdapter *adapter) {
  Compiler c = adapter.compiler;
  Type target = adapter.target, source = adapter.source;
  int target_count = adapter.target_params.len();
  int source_count = adapter.source_params.len();
  if (target_count != source_count) {
    String detail = "target has %d parameters; source has %d".printf(
      target_count, source_count);
    _typed_adapter_error(
      c, "typed callback adapter arity mismatch", target, source, %($detail));
  }
  adapter.target_return = adapter.target_return.canonicalize();
  adapter.source_return = adapter.source_return.canonicalize();
  if (adapter.target_return === %(void) ||
      adapter.source_return === %(void))
    _typed_adapter_error(
      c, "typed callback adapter does not support void return",
      target, source, NULL);
  if (adapter.target_return != adapter.source_return)
    _typed_adapter_error(
      c, "typed callback adapter return type mismatch", target, source, NULL);
}

static void _typed_adapter_parameters(TypedAdapter *adapter) {
  Compiler c = adapter.compiler;
  int index = 0;
  List targets = adapter.target_params, sources = adapter.source_params;
  for (; targets;
       targets = targets.cdr(), sources = sources.cdr(), index++) {
    Type target_param = targets.car();
    Type source_param = sources.car();
    if (!_typed_param_allowed(c, target_param, source_param)) {
      String detail = "parameter %d: %s cannot adapt to %s".printf(
        index + 1, target_param.repr(), source_param.repr());
      _typed_adapter_error(
        c, "typed callback adapter parameter mismatch",
        adapter.target, adapter.source, %($detail));
    }
  }
}

static List _publish_typed_adapter(
  TypedAdapter *adapter, Type target_spelling) {
  Compiler c = adapter.compiler;
  Type target_type = adapter.target;
  List source_binding = adapter.source_binding;
  List key = %(tadapt $source_binding $target_type);
  List adapter_binding = NULL;
  $adapter.memo(c, key, adapter_binding) {
    String adapter_name = c.fresh_name("callback_adapt");
    adapter_binding = c.sym.introduce(adapter_name);
    CallbackBuild build = {
      .compiler = c, .binding = adapter_binding,
      .parameters = adapter.target_params, .result = adapter.target_return,
      .source_binding = source_binding, .source_type = adapter.source,
      .source_parameters = adapter.source_params,
    };
    List function = _callback_function(&build);
    c.semantic_binding_facts()[%(function $adapter_binding)] = 1;
    c.add_early(function);
  }
  return %(expr $target_spelling (ident $adapter_binding));
}

/** Lowers a resolved `tadapt` expression to a typed callback helper.
    `expression` must have the resolved shape
    `(expr TARGET (tadapt ORIGIN (expr SOURCE (ident BINDING))))`.
    Compatible helpers are cached by source binding and target type, queued
    with `Compiler.add_early`, and returned as typed identifiers; other
    expressions pass through unchanged.
*/
List Compiler.lower_typed_adapter_expr(Compiler c, List expression) {
  Type target_spelling = NULL, source_type = NULL;
  List source_binding = NULL, int origin = 0;
  match (expression) {
    case %(expr ?target (tadapt ?at (expr ?source (ident ?binding)))): {
      target_spelling = target;
      source_type = source;
      source_binding = binding;
      origin = at;
    }
    case %(expr ?target (tadapt ?at (expr ?source ?))): {
      $let(c.origin, at) {
        Type target_type = c.sym.resolve_key(target);
        _typed_adapter_error(
          c,
          "typed callback adapter source must be a direct function",
          target_type, source,
          %("supported: a free function or Type.method designator"));
      }
    }
    default: return expression;
  }
  $let(c.origin, origin) {
    TypedAdapter adapter = {
      .compiler = c, .target = c.sym.resolve_key(target_spelling),
      .source = source_type, .source_binding = source_binding,
    };
    _typed_adapter_parts(&adapter);
    _typed_adapter_signature(&adapter);
    _typed_adapter_parameters(&adapter);
    return _publish_typed_adapter(&adapter, target_spelling);
  }
}

static int _func_adapter_source(
  Type type, List payload, Type &source_type, List &source_binding) {
  match (payload) {
    case $source_identifier_content(%(?binding)): {
      if (!type || type.is_pointer() || !type.is_function()) return 0;
      source_type = type;
      source_binding = binding;
      return 1;
    }
    case $source_cast_content(%(? (expr ?inner_type ?inner_payload))):
      return _func_adapter_source(
        inner_type, inner_payload,
        source_type, source_binding);
    case $source_content_pattern($grouped, %(?inner)):
      match (inner)
        case %(expr ?inner_type ?inner_payload):
          return _func_adapter_source(
            inner_type, inner_payload, source_type, source_binding);
    case $source_operator_content(%(& (expr ?inner_type ?inner_payload))):
      return _func_adapter_source(
        inner_type, inner_payload,
        source_type, source_binding);
  }
  return 0;
}

static int _is_func_adapter(Compiler compiler, Type type) {
  if (!type) return 0;
  Type adapter = compiler.sym.resolve_key(%("FuncAdapter"));
  if (!adapter) return 0;
  return compiler.sym.resolve_key(type).equal(adapter);
}

/* A function already written in the adapter's own shape needs no wrapper:
   C converts the designator to a pointer at the call. */
static int _is_func_adapter_target(Compiler compiler, Type type) {
  if (!type) return 0;
  Type adapter = compiler.sym.resolve_key(%("FuncAdapter"));
  if (!adapter || !adapter.is_pointer()) return 0;
  Type pointee = adapter.dereference();
  return type.canonicalize().equal(pointee.canonicalize());
}

static List _adapter_symbol_literal(Symbol value) =>
  %(expr ("Symbol") "${(unsigned long) value}");

static List _integer_expression(int value) =>
  %(expr (int) (literal (int) ${%"$value"}));

static List _adapter_helper(Compiler compiler, String name, Type &type) =>
  compiler.sym.resolve_global(%($name), type);

static List _type_literal(Compiler compiler, Type type) =>
  compiler.cache_literal_list(
    compiler.sym.normalize_declared_type(type));

/** Returns the canonical signature shared by native and meta Func adapters. */
List Compiler.func_signature(Compiler compiler, Type type) {
  List params = NULL;
  Type result = NULL;
  _typed_function_parts(type, params, result);
  Array declared = [];
  foreach (List parameter, params)
    declared.push(parameter.type().declared());
  List parameter_types = params ? declared.list_free() : %((void));
  Type declared_result = result.declared();
  List signature = %((func $parameter_types) @declared_result);
  return signature;
}

static List _func_signature_literal(Compiler compiler, Type type) =>
  compiler.cache_literal_list(compiler.func_signature(type));

typedef struct FuncReaders {
  Compiler compiler;
  Type diagnostic_type;
  List value, reference, fn, argv;
} FuncReaders;

/* Call a resolved adapter reader without rebinding its typed arguments. */
static List _adapter_reader_call(
  FuncReaders readers, Type result_type, List target, int index,
  List details) {
  List fn = %(expr ("Func") (ident ${readers.fn}));
  List argv = %(expr (* const "FuncArg") (ident ${readers.argv}));
  List arguments = %($fn $argv ${_integer_expression(index)} @details);
  return _func_call(readers.compiler, result_type, target, arguments);
}

macro open Expression $func_address(Expr $value) => &$value;

macro open Expression $func_size(Expr $value) => sizeof $value;

macro open Expression $func_dereference(Expr $value) => *$value;

/* Reuse an issued declarator row without binding it again. */
macro open Statement $func_local(
    Type $type, DeclaratorRow $row) {
  $type $row;
}

static List _read_reference_arg(
  FuncReaders readers, Type parameter_type, int index,
  Type &storage_type) {
  Compiler compiler = readers.compiler;
  Type target = parameter_type.cdr(), pointer = target.reference();
  List picked = _adapter_reader_call(
    readers, %(* void), readers.reference, index,
    %(${compiler.cache_literal_list(target)}
      ${_type_literal(compiler, target)}));
  storage_type = pointer;
  return compiler.convert_expression(picked, pointer);
}

static List _read_pointer_arg(
  FuncReaders readers, Type parameter_type, Type resolved, int index,
  Type &storage_type) {
  Compiler compiler = readers.compiler;
  /* A pointer without its own Var tag and a by-value record both arrive as
     `<p48>`; the latter is the address of the record's bytes. */
  Type pointer_type = NULL;
  List pointer_helper = _adapter_helper(
    compiler, "x2c_func_pointer_argument", pointer_type);
  List picked = _adapter_reader_call(
    readers, %(* void), _func_bound(pointer_type, pointer_helper),
    index, NULL);
  storage_type = parameter_type;
  if (resolved.is_pointer())
    return compiler.convert_expression(picked, parameter_type);
  Type record_pointer = parameter_type.reference();
  List pointer = %(expr $record_pointer (cast $record_pointer $picked));
  Macro dereference = $func_dereference;
  return compiler.rebuild_expression(
    parameter_type, dereference(pointer));
}

static List _read_value_arg(
  FuncReaders readers, Type parameter_type, Symbol tag, int index,
  Type &storage_type) {
  Compiler compiler = readers.compiler;
  if (!tag)
    _typed_adapter_error(
      compiler,
      "native binding parameter type has no Var representation",
      readers.diagnostic_type, parameter_type, NULL);
  List picked = _adapter_reader_call(
    readers, %("Var"), readers.value, index,
    %(${_adapter_symbol_literal(tag)}));
  storage_type = parameter_type;
  return compiler.convert_expression(picked, parameter_type);
}

static List _checked_func_argument(
  FuncReaders readers, Type parameter_type, int index, Type &storage_type) {
  if (parameter_type.car() == <&> ||
      parameter_type.car() == <opt-ref>)
    return _read_reference_arg(
      readers, parameter_type, index, storage_type);
  Compiler compiler = readers.compiler;
  Symbol tag = compiler.sym.var_tag_for_type(parameter_type, NULL);
  Type resolved = compiler.sym.resolve_key(parameter_type);
  if (!tag && resolved &&
      (resolved.is_pointer() || resolved.car() == <struct>))
    return _read_pointer_arg(
      readers, parameter_type, resolved, index, storage_type);
  return _read_value_arg(
    readers, parameter_type, tag, index, storage_type);
}

/* Materialize arguments in index order: C does not sequence call operands,
   and a reader failure must prevent later conversions and body effects. */
static List _func_argument_locals(
  Compiler compiler, Type diagnostic_type, List types, List names,
  List fn_binding, List argv_binding) {
  Type value_type = NULL, reference_type = NULL;
  List value_helper = _adapter_helper(
    compiler, "x2c_func_value_argument", value_type);
  List reference_helper = _adapter_helper(
    compiler, "x2c_func_declared_reference_argument", reference_type);
  FuncReaders readers = {
    .compiler = compiler, .diagnostic_type = diagnostic_type,
    .value = _func_bound(value_type, value_helper),
    .reference = _func_bound(reference_type, reference_helper),
    .fn = fn_binding, .argv = argv_binding
  };
  Array locals = [];
  int index = 0;
  Macro local = $func_local;
  foreach (Type type, types) {
    List binding = names.car();
    names = names.cdr();
    Type storage_type = NULL;
    List value = _checked_func_argument(
      readers, type, index++, storage_type);
    List (base, mods) = storage_type.declaration_parts();
    List row = %(op = (bind $binding $mods) $value);
    locals.push(compiler.rebuild_statement(local(base, row)).cadr());
  }
  return locals.list_free();
}

/* One emitted FuncAdapter ABI. Callers order context setup around argument
   locals; the ordinary helper body owner boxes results and preserves
   no-value returns. */
static void _publish_func_adapter(
  Compiler compiler, List binding, List fn_binding, List argv_binding,
  List body, List setup) {
  List parameters = _named_decl_params(
    %(("Func") (* const "FuncArg")), %($fn_binding $argv_binding));
  compiler.add_early(
    compiler.wrapper_function(
      %(static "Var"), binding, parameters.cdr(),
      _helper_body(compiler, body, setup).cdr()));
}

/* A record result is copied into a Var after the native call completes. */
macro open Statement $func_record_result(
    Type $type, DeclaratorRow $row, Expr $boxed) {
  {
    $type $row;
    return $boxed;
  }
}

static List _func_record_call(
  Compiler c, Type return_type, List call) {
  /* A record result is returned as `<p48>` to a copy of its bytes. */
  Type result_type = NULL;
  List result_helper = _adapter_helper(
    c, "x2c_func_record_result", result_type);
  List result = c.sym.introduce(c.fresh_name("func_record"));
  List (base, mods) = return_type.declaration_parts();
  List value = _func_bound(return_type, result);
  Macro address_shape = $func_address, size_shape = $func_size;
  List address = c.rebuild_expression(
    return_type.reference(), address_shape(value));
  List size = c.rebuild_expression(
    %(unsigned long), size_shape(value));
  List helper = %(expr $result_type (ident $result_helper));
  List boxed = _func_call(c, %("Var"), helper, %($address $size));
  Macro record = $func_record_result;
  List row = %(op = (bind $result $mods) $call);
  return c.rebuild_statement(record(base, row, boxed)).cadr();
}

static void _require_func_readers(
  Compiler c, Type diagnostic_type, Type source_type) {
  foreach (String helper_name,
           %("x2c_func_value_argument"
             "x2c_func_declared_reference_argument")) {
    Type helper_type = NULL;
    List helper = _adapter_helper(c, helper_name, helper_type);
    if (!helper || !helper_type)
      _typed_adapter_error(
        c, "native binding needs Func argument readers from lib/func.x",
        diagnostic_type, source_type, NULL);
  }
}

static List _build_func_adapter(
  Compiler c, Type diagnostic_type, Type source_type,
  List target, List supplied_fn_binding, List prefix) {
  List params = NULL, Type return_type = NULL;
  _typed_function_parts(source_type, params, return_type);
  if (_typed_params_variadic(params)) {
    Type func_type = c.sym.resolve_key(%("Func"));
    String message = c.sym.resolve_key(diagnostic_type).equal(func_type)
      ? "function conversion to Func cannot be variadic"
      : "native binding target cannot be variadic";
    _typed_adapter_error(
      c, message, diagnostic_type, source_type, NULL);
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
    names, %!(Type type, List binding) => %(expr $type (ident $binding)));
  List call = _func_call(c, return_type, target, arguments);
  Type resolved_result = c.sym.resolve_key(return_type);
  if (resolved_result && resolved_result.car() == <struct>)
    call = _func_record_call(c, return_type, call);
  _publish_func_adapter(
    c, adapter_binding, fn_binding, argv_binding, call, %(@prefix @locals));
  return adapter_binding;
}

static List _direct_func_adapter(
  Compiler compiler, Type diagnostic_type,
  List source_binding, Type source_type) {
  Type key_type = source_type.canonicalize();
  List key = %(fadapt $source_binding $key_type);
  List adapter = NULL;
  $adapter.memo(compiler, key, adapter) {
    List target = %(expr $source_type (ident $source_binding));
    adapter = _build_func_adapter(
      compiler, diagnostic_type, source_type, target, NULL, NULL);
  }
  return adapter;
}

static int _direct_func_source(
  Type type, List payload, Type &source_type, List &source_binding) {
  match (payload) {
    case $source_identifier_content(%(?binding)): {
      if (!type || type.is_pointer() || !type.is_function()) return 0;
      source_type = type;
      source_binding = binding;
      return 1;
    }
    case $source_content_pattern($grouped, %(?inner)):
      match (inner)
        case %(expr ?inner_type ?inner_payload):
          return _direct_func_source(
            inner_type, inner_payload, source_type, source_binding);
    case $source_operator_content(%(& (expr ?inner_type ?inner_payload))):
      return _direct_func_source(
        inner_type, inner_payload, source_type, source_binding);
  }
  return 0;
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
  if (!_func_adapter_source(
    arg_type, payload, source_type, source_binding)) {
    _typed_adapter_error(
      c, "native binding target must be a direct function",
      expected_type, arg_type,
      %("supported: a free function or Type.method designator"));
  }
  if (_is_func_adapter_target(c, source_type)) return argument;
  List adapter = _direct_func_adapter(
    c, expected_type, source_binding, source_type);
  return %(expr $expected_type (ident $adapter));
}

static int _func_type_qualifier(Var value) =>
  value == <const> || value == <volatile> || value == <restrict>;

static Type _func_pointer_value_type(Compiler compiler, Type type) {
  Type resolved = compiler.sym.resolve_key(type);
  if (resolved) type = resolved;
  while (type && _func_type_qualifier(type.car())) type = type.cdr();
  if (!type || type.car() != <*>) return NULL;
  List tail = type.cdr();
  while (tail && _func_type_qualifier(tail.car())) tail = tail.cdr();
  Type pointer = cons(<*>, tail);
  return pointer.dereference().is_function() ? pointer : NULL;
}

macro open Statement $func_static_handle(Name $handle, Expr $value) {
  static Func $handle = $value;
}

macro open Statement $func_bridge_prototype(
    Name $bridge, Param $parameters...) {
  extern Func $bridge($parameters...);
}

macro open Expression $func_aggregate(Expr $value) => { $value };

macro open Expression $func_present(
    Expr $pointer, Expr $value, Expr $fallback) =>
  $pointer ? $value : $fallback;

/* A Name expression hole leaves an untyped inner shell. Keep the issued
   identity in its canonical typed expression until rebuild can remove it. */
static List _func_bound(Type type, List binding) =>
  %(expr $type (ident $binding));

static List _func_call(
  Compiler compiler, Type type, List callee, List arguments) {
  Macro shape = $called;
  return compiler.rebuild_expression(type, shape(callee, arguments));
}

static List _func_return_body(Compiler compiler, List value) {
  Macro shape = $return_value;
  return compiler.rebuild_statement(shape(value)).cdr();
}

static void _func_pointer_context(
  Compiler compiler, Type pointer_type, String &context_name,
  List &field_binding) {
  context_name = compiler.fresh_name("func_pointer_context");
  List context_binding = compiler.sym.introduce(context_name);
  field_binding = compiler.sym.introduce(
    compiler.fresh_name("func_pointer"));
  List (field_base, field_mods) = pointer_type.declaration_parts();
  compiler.add_early(
    %(
    typedef
      (struct $context_name
        (fields
          (declare $field_base
            (bindings (bind $field_binding $field_mods)))))
      (bindings (bind $context_binding ()))
  ));
}

static List _build_indirect_func_adapter(
  Compiler compiler, Type diagnostic_type, Type pointer_type) {
  String context_name = NULL;
  List field_binding = NULL;
  _func_pointer_context(
    compiler, pointer_type, context_name, field_binding);
  Type context_type = %($context_name);
  Type context_pointer = %(* const $context_name);
  Type context_helper_type = NULL;
  List context_helper = _adapter_helper(
    compiler, "Func_context", context_helper_type);
  if (!context_helper || !context_helper_type)
    _typed_adapter_error(
      compiler, "native binding needs Func.context from lib/func.x",
      diagnostic_type, pointer_type, NULL);
  List fn_binding = compiler.sym.introduce(
    compiler.fresh_name("func_binding"));
  List context_value = _func_call(
    compiler, %(* const void),
    _func_bound(context_helper_type, context_helper),
    %(${_func_bound(%("Func"), fn_binding)}));
  List context_local = compiler.sym.introduce(
    compiler.fresh_name("func_pointer_context"));
  List cast = %(expr $context_pointer
    (cast $context_pointer $context_value));
  Macro storage_shape = $func_local;
  List context_declaration = compiler.rebuild_statement(
    storage_shape(
      %(const $context_name),
      %(op = (bind $context_local (*)) $cast))).cadr();
  String field_name = binding_identity_spelling(field_binding);
  List context = _func_bound(context_pointer, context_local);
  List target = %(
    expr $pointer_type (op -> $context ($field_name)));
  List adapter = _build_func_adapter(
    compiler, diagnostic_type, pointer_type, target, fn_binding,
    %($context_declaration));
  return %(indirect-adapter $adapter $context_type $field_binding);
}

static List _indirect_func_adapter(
  Compiler compiler, Type diagnostic_type, Type pointer_type,
  Type &out_context_type, List &out_context_field) {
  List key = %(findirect $pointer_type), result = NULL;
  $adapter.memo(compiler, key, result) {
    result = _build_indirect_func_adapter(
      compiler, diagnostic_type, pointer_type);
  }
  (List adapter, Type context, List field) = result.cdr();
  out_context_type = context;
  out_context_field = field;
  return adapter;
}

static List _direct_func_handle(
  Compiler compiler, List source_binding, Type source_type) {
  Type key_type = source_type.canonicalize();
  List key = %(fhandle $source_binding $key_type);
  List handle = NULL;
  $adapter.memo(compiler, key, handle) {
  List adapter = _direct_func_adapter(
    compiler, %("Func"), source_binding, source_type);
  List signature = _func_signature_literal(compiler, source_type);
  Type constructor_type = NULL;
  List constructor = _adapter_helper(
    compiler, "Func_new", constructor_type);
  if (!constructor || !constructor_type)
    _typed_adapter_error(
      compiler, "function conversion needs Func.new from lib/func.x",
      %("Func"), source_type, NULL);
  handle = compiler.sym.introduce(
    compiler.fresh_name("func_handle"));
  List value = _func_call(
    compiler, %("Func"),
    _func_bound(constructor_type, constructor),
    %(${_func_bound(%("FuncAdapter"), adapter)} $signature));
  Macro shape = $func_static_handle;
  compiler.add_early(
    compiler.rebuild_statement(shape(handle, value)).cadr());
  }
  return _func_bound(%("Func"), handle);
}

static List _func_bridge_binding(Compiler compiler, String stem) {
  String hash = "%08x".printf(compiler.filename.hash());
  return compiler.sym.introduce(
    compiler.fresh_name(%"${stem}_$hash"));
}

static List _func_bridge_call(
  Compiler compiler, List bridge, List parameters,
  Type function_type, List arguments) {
  Macro prototype_shape = $func_bridge_prototype;
  List prototype = compiler.rebuild_statement(
    prototype_shape(bridge, parameters.cdr())).cadr();
  List call = _func_call(
    compiler, %("Func"),
    _func_bound(function_type, bridge), arguments);
  Macro statement_shape = $expression_statement;
  List statement = compiler.rebuild_statement(
    statement_shape(call)).cadr();
  return %(
    expr ("Func") (parens (block $prototype $statement))
  );
}

static List _direct_func_value(
  Compiler compiler, List source_binding, Type source_type) {
  List handle = _direct_func_handle(
    compiler, source_binding, source_type);
  if (!compiler.inline_header) return handle;

  Type key_type = source_type.canonicalize();
  List key = %(fgetter $source_binding $key_type);
  List bridge = NULL;
  List parameters = %(params (param (void) (bind () ())));
  $adapter.memo(compiler, key, bridge) {
    bridge = _func_bridge_binding(compiler, "func_get");
    compiler.add_early(
      compiler.wrapper_function(
        %("Func"), bridge, parameters.cdr(),
        _func_return_body(compiler, handle)));
  }
  Type getter_type = %((func ((void))) "Func");
  return _func_bridge_call(
    compiler, bridge, parameters, getter_type, NULL);
}

typedef struct FuncContextCall {
  Compiler compiler;
  Type type, adapter_type, constructor_type;
  List context, adapter, signature, constructor;
} FuncContextCall;

static List _func_context_call(FuncContextCall *call) {
  Compiler compiler = call.compiler;
  Type type = call.type;
  List context = call.context;
  List value = _func_bound(type, context);
  Macro address_shape = $func_address;
  List address = compiler.rebuild_expression(
    type.reference(), address_shape(value));
  Macro size_shape = $func_size;
  List size = compiler.rebuild_expression(
    %(size_t), size_shape(value));
  return _func_call(
    compiler, %("Func"),
    _func_bound(call.constructor_type, call.constructor),
    %(${_func_bound(call.adapter_type, call.adapter)}
      ${call.signature} $address $size));
}

static List _func_present_statement(
  Compiler compiler, List pointer, List constructed) {
  List null_binding = compiler.sym.reference(%("NULL"), NULL);
  Macro present_shape = $func_present;
  List result = compiler.rebuild_expression(
    %("Func"),
    present_shape(
      pointer, constructed, _func_bound(%("Func"), null_binding)));
  Macro statement_shape = $expression_statement;
  return compiler.rebuild_statement(statement_shape(result)).cadr();
}

static List _func_context_declaration(
  Compiler compiler, Type context_type, List context, List expression) {
  Macro aggregate_shape = $func_aggregate;
  List value = compiler.rebuild_expression(
    context_type, aggregate_shape(expression));
  Macro storage_shape = $func_local;
  return compiler.rebuild_statement(
    storage_shape(
      context_type, %(op = (bind $context ()) $value))).cadr();
}

static List _indirect_func_value(
  Compiler compiler, List expression, Type pointer_type) {
  Type context_type = NULL;
  List context_field = NULL;
  List adapter = _indirect_func_adapter(
    compiler, %("Func"), pointer_type,
    context_type, context_field);
  List signature = _func_signature_literal(compiler, pointer_type);
  Type constructor_type = NULL;
  List constructor = _adapter_helper(
    compiler, "Func_new_context", constructor_type);
  if (!constructor || !constructor_type)
    _typed_adapter_error(
      compiler,
      "function pointer conversion needs Func.new_context from lib/func.x",
      %("Func"), pointer_type, NULL);

  List context = compiler.sym.introduce(
    compiler.fresh_name("func_pointer_context"));
  List declaration = _func_context_declaration(
    compiler, context_type, context, expression);
  String field_name = binding_identity_spelling(context_field);
  List pointer = %(
    expr $pointer_type
      (op . ${_func_bound(context_type, context)} ($field_name)));
  FuncContextCall call = {
    .compiler = compiler, .type = context_type, .context = context,
    .adapter = adapter, .adapter_type = %("FuncAdapter"),
    .signature = signature, .constructor = constructor,
    .constructor_type = constructor_type,
  };
  List constructed = _func_context_call(&call);
  List statement = _func_present_statement(compiler, pointer, constructed);
  return %(
    expr ("Func") (parens (block $declaration $statement))
  );
}

static List _indirect_func_lift(
  Compiler compiler, List expression, Type pointer_type) {
  if (!compiler.inline_header)
    return _indirect_func_value(compiler, expression, pointer_type);

  Type key_type = pointer_type.canonicalize();
  List key = %(fpointer-factory $key_type);
  List bridge = NULL;
  $adapter.memo(compiler, key, bridge) {
    bridge = _func_bridge_binding(compiler, "func_from_pointer");
    List parameter = compiler.sym.introduce(
      compiler.fresh_name("func_pointer"));
    List parameters = %(
      params ${pointer_type.parameter_ast(parameter)}
    );
    List value = _indirect_func_value(
      compiler, _func_bound(pointer_type, parameter), pointer_type);
    compiler.add_early(
      compiler.wrapper_function(
        %("Func"), bridge, parameters.cdr(),
        _func_return_body(compiler, value)));
  }
  List parameters = %(
    params ${pointer_type.parameter_ast(NULL)}
  );
  Type factory_type = %((func ($pointer_type)) "Func");
  return _func_bridge_call(
    compiler, bridge, parameters, factory_type, %($expression));
}

/* A dereferenced function pointer reaches the lift untyped or typed as a
   bare pointer, possibly under parens or address-of shells; recover the
   callable type from the pointer operand. Unsupported shapes pass through. */
static List _deref_func_lift(
  Compiler compiler, List expression, List payload) {
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
      Type resolved = compiler.sym.resolve_key(operand_type);
      if (resolved && resolved.is_pointer() &&
          resolved.dereference().is_function())
        return _indirect_func_lift(
          compiler, %(expr $resolved $payload), resolved);
    }
  return expression;
}

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
  if (c.sym.resolve_key(type).equal(func_type)) return expression;

  Macro lambda = $lambda_expression;
  match (expression)
    case lambda(?body, *params): {
      expression = c.lower_lambda_expr(expression);
      match (expression)
        case %(expr ?lowered_type ?lowered_payload): {
          type = lowered_type;
          payload = lowered_payload;
        }
      if (c.sym.resolve_key(type).equal(func_type))
        return expression;
    }

  Type source_type = NULL;
  List source_binding = NULL;
  if (_direct_func_source(type, payload, source_type, source_binding))
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

static int _lambda_adapter_signature(
  List expected_type, List &raw_params, Var &return_type) {
  if (!expected_type) return 0;
  Type expected = expected_type;
  expected = expected.canonicalize();
  if (!expected) expected = expected_type;
  match (expected) {
    case %((func (*parameters)) ?return_head *): {
      raw_params = parameters;
      return_type = return_head;
      return 1;
    }
    case %((!or (!quote *) & ^)
           (func (*parameters)) ?return_head *): {
      raw_params = parameters;
      return_type = return_head;
      return 1;
    }
  }
  return 0;
}

typedef struct LambdaAdapter {
  Compiler compiler;
  List expected_type, param_types, return_type;
  List source_binding, source_param_types;
  Type source_type;
} LambdaAdapter;

static List _publish_lambda_adapter(LambdaAdapter *adapter) {
  Compiler c = adapter.compiler;
  String name = c.fresh_name("lambda_adapt");
  List binding = c.sym.introduce(name);
  CallbackBuild build = {
    .compiler = c, .binding = binding,
    .parameters = adapter.param_types, .result = adapter.return_type,
    .source_binding = adapter.source_binding,
    .source_type = adapter.source_type,
    .source_parameters = adapter.source_param_types,
  };
  List callback = _callback_function(&build);
  c.add_early(callback);
  return %(expr ${adapter.expected_type} (ident $binding));
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
  Type orig_type = NULL, List orig_binding = NULL;
  match (argument) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}): {
      List adapted = c.adapt_lambda_arg(inner, expected_type);
      if (adapted == inner) return argument;
      Macro grouped = $grouped;
      return c.rebuild_expression(expected_type, grouped(adapted));
    }
    case %(expr ?type ${$source_identifier_content(%(?binding))}): {
      orig_type = type;
      orig_binding = binding;
    }
    default: return argument;
  }
  List raw_params = NULL;
  Var return_type = void;
  if (!_lambda_adapter_signature(expected_type, raw_params, return_type))
    return argument;
  if (_typed_params_variadic(raw_params)) return argument;

  List param_types = NULL;
  int all_params_var = _collect_param_types(raw_params, param_types);
  List source_params = NULL, source_param_types = NULL;
  _typed_function_parts(orig_type, source_params, NULL);
  _collect_param_types(source_params, source_param_types);
  List return_type_list = return_type is <list>
    ? return_type : %( $return_type );
  if (all_params_var && return_type_list === %("Var")) return argument;

  LambdaAdapter adapter = {
    .compiler = c, .expected_type = expected_type,
    .param_types = param_types, .return_type = return_type_list,
    .source_binding = orig_binding, .source_type = orig_type,
    .source_param_types = source_param_types,
  };
  return _publish_lambda_adapter(&adapter);
}

static Type _entry_type(Compiler compiler, List entry) {
  match (entry) {
    case %(binding ? ?): return %("Var");
    case %(param ? ?): {
      Type type = entry.type_from_ast().declared();
      if (type.car() == <&> || type.car() == <opt-ref>)
        return cons(
          type.car(), compiler.sym.normalize_declared_type(type.cdr()));
      return type;
    }
  }
  return NULL;
}

static List _entry_binding(List entry) {
  match (entry) {
    case %(!set ?binding (binding ? ?)): return binding;
    case %(param ? (bind ?binding *)): return binding;
  }
  return NULL;
}

static List _signature(Compiler compiler, List entries) {
  List parameters = compiler.lambda_param_types(entries);
  return compiler.cache_literal_list(%((func $parameters) "Var"));
}

static int _cell_parts(
  Map cells, List binding, List &cell, Type &type) {
  Var stored;
  if (!cells.try_get(binding, stored)) return 0;
  match (stored)
    case %(lambda-cell ?matched_cell ?matched_type): {
      cell = matched_cell;
      type = matched_type;
      return 1;
    }
  return 0;
}

static void _record_region_binding(
  Compiler compiler, List binding, Map owned, Array order) {
  if (!binding || binding in owned) return;
  Var automatic, stored_type;
  Map facts = compiler.semantic_binding_facts();
  if (!facts.try_get(%(automatic $binding), automatic) ||
      !facts.try_get(%(type $binding), stored_type))
    return;
  Type type = stored_type;
  if (!type || type.is_static()) return;
  owned[binding] = type;
  order.push(binding);
}

/* Collect only bindings owned by this callable region. Nested lambdas are
   separate regions even though their capture expressions execute here.
   Keep the manual worklist: a Func visit callback's dynamic call per node
   cost ~6% of self-translation.
   Pending sibling suffixes wait on `resume` to stay off the C stack. */
static void _collect_region_bindings(
  Compiler compiler, List ast, Map owned, Array order) {
  if (!ast) return;
  Array resume = $auto([]);
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  for (;;) {
    int pruned = 0;
    match (ast) {
      case lambda(?body, *params): pruned = 1;
      case captured(?body, *captures, *params): pruned = 1;
      case %(bind ?binding *): {
        _record_region_binding(compiler, binding, owned, order);
        pruned = 1;
      }
    }
    List rest = pruned ? NULL : ast;
    for (;;) {
      while (!rest) {
        if (!resume.len()) return;
        rest = resume.take_last();
      }
      Var child = rest.car();
      rest = rest.cdr();
      if (child is <list> && !child.is_nil()) {
        if (rest) resume.push(rest);
        ast = child;
        break;
      }
    }
  }
}

/* Return the binding whose stored object an lvalue names. Pointer
   dereferences and pointer indexes name another object; an array field
   remains part of its containing aggregate. */
static List _lvalue_binding(List ast) {
  if (!ast) return NULL;
  match (ast) {
    case %(expr ? ${$source_identifier_content(%(?binding))}):
      return binding;
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return _lvalue_binding(inner);
    case $source_content_pattern($grouped, %(?inner)):
      return _lvalue_binding(inner);
    case %(expr ? ${$source_operator_content(%(. ?base *))}):
      return _lvalue_binding(base);
    case $source_operator_content(%(. ?base *)):
      return _lvalue_binding(base);
    case $source_pattern_with($indexed, %(?receiver ?selector),
        %((?receiver (expr ((dim *) *) ?base)) (?selector ?))):
      return _lvalue_binding(base);
  }
  return NULL;
}

static void _require_capture_lvalue(Compiler c, List target) {
  List binding = _lvalue_binding(target);
  if (binding &&
      %(lambda-snapshot $binding) in c.semantic_binding_facts())
    c.report_error(
      <type>, "captured value requires 'using &name' for reference access",
      c.token, %("binding: ${binding_identity_spelling(binding)}"));
}

/** Rejects writes and reference access to read-only snapshot bindings.
    The body has already resolved identifiers and call arguments. Templates
    defer this check until expansion; nested lambdas check their own bodies.
*/
void Compiler.check_lambda_captures(Compiler c, List ast) {
  if (c.macro_holes) return;
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  Array pending = $auto([]);
  pending.push(ast);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node) {
      case lambda(?body, *params): continue;
      case captured(?body, *captures, *params): continue;
      case $source_operator_content(%(& ?target)):
        _require_capture_lvalue(c, target);
      case $source_operator_content(%(?operator ?target *)):
        if (operator is <symbol> && ast_changes_left_operand(operator))
          _require_capture_lvalue(c, target);
      case $source_postfix_content(%(? ?target)):
        _require_capture_lvalue(c, target);
      case %(dstrasgn (targets *targets) ?):
        foreach (List target, targets) _require_capture_lvalue(c, target);
      case $source_call_content($called,
          %(expr ?callee_type ?), %(*arguments)): {
        List parameters = NULL;
        if (_typed_function_parts(callee_type, parameters, NULL))
          for (; parameters && arguments;
               parameters = parameters.cdr(), arguments = arguments.cdr()) {
            Type parameter = parameters.car();
            if (parameter.car() == <&> || parameter.car() == <opt-ref>)
              _require_capture_lvalue(c, arguments.car());
          }
      }
    }
    foreach (Var child, node) pending.push(child);
  }
}

static void _collect_reference_captures(
  List ast, Map owned, Map candidates) {
  Array pending = $auto([]);
  pending.push(ast);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node)
      case %(capture ? (& *) (expr ? (op & ?target))): {
        List binding = _lvalue_binding(target);
        Var stored;
        if (binding && owned.try_get(binding, stored)) {
          Type type = stored;
          if (type.car() != <&>) candidates[binding] = type;
        }
      }
    foreach (Var child, node) pending.push(child);
  }
}

/* A shared lambda cell: Scope storage for one automatic binding, copied
   from its initializer or left for a later assignment. */
macro open Statement $compiler_cell(Type $type, Name $cell, Expr $value) {
  $type *$cell = Scope_memdup((const void *)&($type)$value, sizeof($type));
}

macro open Statement $compiler_empty_cell(Type $type, Name $cell) {
  $type *$cell = Scope_malloc(sizeof($type));
}

macro open Expression $compiler_cell_value(Name $cell) => (*$cell);

/* A plain initializer is the one element of the compound a cell copies. */
static List _cell_declaration(
  Compiler c, List cell, Type type, List initializer) {
  List compound = initializer;
  if (initializer && !initializer.match(%(expr ? (composite ?))))
    compound = %(expr () (composite (commas $initializer)));
  Macro shape = initializer ? $compiler_cell : $compiler_empty_cell;
  return c.bind_syntax(shape(type, cell, compound), AST_BLOCK, NULL);
}

/* Split only declarations that need cells. Keeping each cell allocation at
   its binding preserves declaration order and evaluates its initializer once;
   moving allocations to lambda construction would reorder visible effects. */
static List _rewrite_lambda_declaration(
  Compiler compiler, List target, List bindings, Map cells) {
  int has_cell = 0;
  foreach (List item, bindings) {
    List binding = NULL;
    match (item) {
      case %(bind ?matched *): binding = matched;
      case %(op = (bind ?matched *) ?): binding = matched;
    }
    has_cell |= binding && binding in cells;
  }
  if (!has_cell) return NULL;

  Array sequence = [];
  foreach (List item, bindings) {
    List binding = NULL, initializer = NULL;
    match (item) {
      case %(bind ?matched *): binding = matched;
      case %(op = (bind ?matched *) ?value): {
        binding = matched;
        initializer = _rewrite_lambda_cells(
          compiler, value, cells);
      }
    }
    List cell = NULL;
    Type type = NULL;
    if (_cell_parts(cells, binding, cell, type)) {
      sequence.push(
        _cell_declaration(
          compiler, cell, type, initializer));
      continue;
    }
    sequence.push(
      %(declare $target (bindings
          ${_rewrite_lambda_cells(compiler, item, cells)})));
  }
  return %(seq @{sequence.list_free()});
}

static List _rewrite_lambda_cells(
  Compiler compiler, List ast, Map cells) {
  if (!ast) return ast;
  match (ast) {
    case %(declare ?target (bindings *bindings)): {
      List declaration = _rewrite_lambda_declaration(
        compiler, target, bindings, cells);
      if (declaration) return declaration;
    }
    case %(expr ?source_type
        ${$source_identifier_content(%(?binding))}): {
      List cell = NULL;
      Type type = NULL;
      if (_cell_parts(cells, binding, cell, type)) {
        if (source_type.car() == <&>)
          return %(expr $source_type (ident $cell));
        Macro value = $compiler_cell_value;
        return compiler.bind_syntax(value(cell), AST_EXPRESSION, NULL);
      }
      return ast;
    }
  }
  return Ast.rewrite_children(
    ast, %!(List child) => _rewrite_lambda_cells(compiler, child, cells));
}

/* Nested bodies own their local cells; their construction expressions still
   execute in the enclosing region. Capture resolution has already assigned
   each binding its value or reference mode. */
static List _prepare_nested_lambda_regions(
  Compiler compiler, List ast) {
  if (!ast) return ast;
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  if (ast.car() == <expr>) {
    match (ast) {
      case captured(?body, *captures, *entries): {
        List prepared = _prepare_lambda_region(compiler, entries, body);
        return prepared == body ? ast : compiler.rebuild_expression(
          ast.cadr(), captured(prepared, captures, entries));
      }
      case lambda(?body, *params): {
        List prepared = _prepare_lambda_region(compiler, params, body);
        return prepared == body ? ast
             : compiler.rebuild_expression(
               ast.cadr(), lambda(prepared, params));
      }
    }
  }

  return Ast.rewrite_children(
    ast, %!(List child) => ast_contains_head(child, <lambda>)
      ? _prepare_nested_lambda_regions(compiler, child) : child);
}

static List _parameter_setup(
  Compiler compiler, List entries, Map cells) {
  Array setup = [];
  foreach (List entry, entries) {
    List binding = _entry_binding(entry);
    List cell = NULL;
    Type type = NULL;
    if (!_cell_parts(cells, binding, cell, type)) continue;
    setup.push(
      _cell_declaration(
        compiler, cell, type,
        %(expr $type (ident $binding))));
  }
  return setup.list_free();
}

static List _prepend_setup(List body, List setup) {
  if (!setup) return body;
  match (body) {
    case $source_block_content(%(*items)):
      return source_block_content(%(@setup @items));
    case %(!set ?expression (expr ?type ?)):
      return %(
        expr $type
          (parens (block @setup (stmnt $expression)))
      );
  }
  return body;
}

/* Explicit reference rows select which automatic bindings need typed cells.
   Parameters allocate at entry and locals at their declarations, preserving
   initializer order. Snapshot rows retain their separate binding
   identities. */
static List _prepare_lambda_region(
  Compiler compiler, List entries, List body) {
  if (!ast_contains_head(body, <lambda>)) return body;
  body = _prepare_nested_lambda_regions(compiler, body);
  Map owned = {};
  Array order = [];
  foreach (List entry, entries)
    _record_region_binding(
      compiler, _entry_binding(entry), owned, order);
  _collect_region_bindings(
    compiler, body, owned, order);

  Map candidates = {};
  _collect_reference_captures(body, owned, candidates);
  if (!candidates.len()) return body;

  Map cells = {};
  foreach (List binding, order) {
    Var stored_type;
    if (!candidates.try_get(binding, stored_type)) continue;
    Type type = stored_type;
    List cell = compiler.sym.introduce(
      compiler.fresh_name("lambda_cell"));
    cells[binding] = %(lambda-cell $cell $type);
    compiler.semantic_binding_facts()[%(automatic $cell)] = 1;
    compiler.semantic_binding_facts()[%(type $cell)] = type.reference();
  }
  List rewritten = _rewrite_lambda_cells(
    compiler, body, cells);
  return _prepend_setup(
    rewritten, _parameter_setup(compiler, entries, cells));
}

/** Prepares one resolved function body for shared mutable lambda captures.
    `declarator` must carry a resolved `bind` with `fnmod` parameters, and
    `body` must agree with the automatic-binding and type facts in `Compiler`.
    Before normal body transformation, the method rewrites explicitly shared
    parameters and locals to `Scope`-owned cells, prepares nested bodies,
    and returns the rewritten body with declaration and initializer order
    preserved.
*/
List Compiler.prepare_lambda_cells(Compiler c, List declarator, List body) {
  List entries = NULL;
  match (declarator)
    case %(bind ? ((fnmod (params *parameters)))):
      entries = parameters;
  return _prepare_lambda_region(c, entries, body);
}

/* Rewrite capture-construction expressions through this environment, but do
   not enter a nested lambda body. Its own environment and lowering handle
   that body once the rewritten capture values are available. */
typedef struct CaptureRewrite {
  Compiler compiler;
  Map slots;
  List environment_binding;
  Type environment_type;
} CaptureRewrite;

static List _capture_rows(
  Compiler compiler, List captures, Map slots, List environment_binding,
  Type environment_type) {
  return Ast.rewrite_children(
    captures, %!(List record) => {
    match (record)
      case %(capture ?binding ?type ?expression): {
        List value = _rewrite_lambda_captures(
          compiler, expression, slots, environment_binding,
          environment_type);
        if (value != expression) return %(capture $binding $type $value);
      }
    return record;
  });
}

static List _capture_read(
  CaptureRewrite *context, List ast, Type source_type, List bound) {
  Var stored;
  if (!context.slots.try_get(bound, stored)) return ast;
  List field = NULL;
  Type storage_type = NULL;
  match (stored)
    case %(capture-field ?matched_field ?matched_type): {
      field = matched_field;
      storage_type = matched_type;
    }
  String field_name = binding_identity_spelling(field);
  Type environment_type = context.environment_type;
  List environment_binding = context.environment_binding;
  List read = %(
    expr $storage_type
      (op -> (expr $environment_type (ident $environment_binding))
             ($field_name))
  );
  if (source_type.car() == <&>)
    return %(expr $source_type ${read.caddr()});
  List converted = context.compiler.convert_expression(read, source_type);
  match (converted)
    case %(expr ? (call "Var_pointer" ?)):
      return %(expr $source_type
               (parens (expr $source_type
                 (cast $source_type $converted))));
  return converted;
}

static List _rewrite_lambda_captures(
  Compiler compiler, List ast, Map slots, List environment_binding,
  Type environment_type) {
  if (!ast) return ast;
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  if (ast.car() == <expr>) {
    match (ast) {
      case captured(?body, *captures, *params): {
        List rewritten = _capture_rows(
          compiler, captures, slots, environment_binding,
          environment_type);
        return rewritten == captures ? ast
             : compiler.rebuild_expression(
               ast.cadr(), captured(body, rewritten, params));
      }
      case lambda(?body, *params): return ast;
      case %(expr ?source_type
          ${$source_identifier_content(%(?bound))}): {
        CaptureRewrite context = {
          .compiler = compiler, .slots = slots,
          .environment_binding = environment_binding,
          .environment_type = environment_type,
        };
        return _capture_read(&context, ast, source_type, bound);
      }
    }
  }

  return Ast.rewrite_children(
    ast, %!(List child) => _rewrite_lambda_captures(
      compiler, child, slots, environment_binding, environment_type));
}

static List _no_value_return(void) => %(
    return ("Var") (expr ("Var") (literal ("Var") "void"))
  );

/* A block lambda returns void for a bare return and for
   fallthrough. Nested lambdas normalize their own returns when lowered. */
static List _block_returns(List ast) {
  if (!ast) return ast;
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  match (ast) {
    case lambda(?body, *params): return ast;
    case captured(?body, *captures, *params): return ast;
    case $source_return_content(%()): return _no_value_return();
  }
  return Ast.rewrite_children(ast, _block_returns);
}

static List _helper_body(
  Compiler compiler, List body, List setup) {
  match (body) {
    case $source_block_content(%(*items)): {
      List normalized = _block_returns(items);
      return source_block_content(
        %(@setup @normalized ${_no_value_return()}));
    }
    case %(expr (void) ?):
      return source_block_content(
        %(@setup (stmnt $body) ${_no_value_return()}));
  }
  List result = compiler.convert_expression(body, %("Var"));
  return source_block_content(%(@setup (stmnt (return $result))));
}

/* File-static context storage shared by captured lambdas and callable
   defers. Bind the complete typedef so each field keeps its member type. */
macro open Unit $capture_environment(Name $name, Field $fields...) {
  typedef struct $name { $fields... } $name;
}

macro open Statement $capture_factory(Statement $storage, Expr $value) {
  $storage
  return $value;
}

/* Capture rows arrive resolved and in first-use order from `literals.x`.
   Their locals run before the context aggregate; value fields are snapshots
   and reference fields retain caller or cell addresses. */
typedef struct CaptureBuild {
  Compiler compiler;
  List entries, body, adapter, closure, argv, environment_type_binding;
  List environment_local, constructor, signature;
  String environment_name;
  Type value_type, pointer_type, adapter_type, constructor_type;
  Map slots;
  Array fields, field_types, locals, values;
} CaptureBuild;

static void _capture_field(CaptureBuild &build, List capture) {
  match (capture)
    case %(capture ?binding ?captured_type ?expression): {
      Compiler c = build.compiler;
      Type source_type = captured_type;
      Type storage_type = source_type.car() == <&>
                        ? source_type.cdr().type().reference()
                        : %("Var");
      List field = c.sym.introduce(c.fresh_name("lambda_capture"));
      List (field_base, field_mods) = storage_type.declaration_parts();
      build.fields.push(
        %(declare $field_base (bindings (bind $field $field_mods))));
      build.field_types.push(storage_type);
      build.slots[binding] = %(capture-field $field $storage_type);

      List temporary = c.sym.introduce(
        c.fresh_name("lambda_capture_value"));
      List value = c.convert_expression(expression, storage_type);
      List (base, mods) = storage_type.declaration_parts();
      Macro local = $func_local;
      List row = %(op = (bind $temporary $mods) $value);
      build.locals.push(c.rebuild_statement(local(base, row)).cadr());
      build.values.push(_func_bound(storage_type, temporary));
    }
}

static void _capture_environment(CaptureBuild &build, List captures) {
  Compiler c = build.compiler;
  foreach (List capture, captures) _capture_field(build, capture);
  Macro environment = $capture_environment;
  c.add_early(
    c.bind_syntax(
      environment(build.environment_type_binding, build.fields.list_free()),
      AST_UNIT, NULL));
}

/* The adapter borrows the copied context for each synchronous Func call. */
static void _capture_adapter(CaptureBuild &build) {
  Compiler c = build.compiler;
  Type context_type = NULL;
  List context_helper = _adapter_helper(c, "Func_context", context_type);
  build.constructor = _adapter_helper(
    c, "Func_new_context", build.constructor_type);
  build.adapter_type = c.sym.resolve_key(%("FuncAdapter"));
  List types = build.entries.map(
    %!(List entry) => _entry_type(c, entry));
  List names = build.entries.map(_entry_binding);
  List locals = _func_argument_locals(
    c, build.adapter_type, types, names, build.closure, build.argv);
  List context_call = _func_call(
    c, %(* const void), _func_bound(context_type, context_helper),
    %(${_func_bound(%("Func"), build.closure)}));
  List context_cast = %(expr ${build.pointer_type}
    (cast ${build.pointer_type} $context_call));
  Macro local = $func_local;
  List context_setup = c.rebuild_statement(
    local(
      %(const ${build.environment_name}),
      %(op = (bind ${build.environment_local} (*)) $context_cast))).cadr();
  List rewritten = _rewrite_lambda_captures(
    c, build.body, build.slots, build.environment_local,
    build.pointer_type);
  rewritten = _node(c, rewritten);
  _publish_func_adapter(
    c, build.adapter, build.closure, build.argv, rewritten,
    %(@locals $context_setup));
  build.signature = _signature(c, build.entries);
}

static List _capture_construct(CaptureBuild &build, List context) {
  FuncContextCall call = {
    .compiler = build.compiler, .type = build.value_type,
    .context = context, .adapter = build.adapter,
    .adapter_type = build.adapter_type, .signature = build.signature,
    .constructor = build.constructor,
    .constructor_type = build.constructor_type,
  };
  return _func_context_call(&call);
}

static List _capture_storage(
  CaptureBuild &build, List context, List values) {
  List initializer = %(expr ${build.value_type}
    (composite (commas @values)));
  Macro local = $func_local;
  return build.compiler.rebuild_statement(
    local(
      build.value_type, %(op = (bind $context ()) $initializer))).cadr();
}

static List _capture_result(
  CaptureBuild &build, List storage, List value) {
  Macro statement_shape = $expression_statement;
  List statement = build.compiler.rebuild_statement(
    statement_shape(value)).cadr();
  List setup = storage ? %($storage) : NULL;
  return %(
    expr ("Func")
      (parens (block @{build.locals.list_free()} @setup $statement))
  );
}

static List _capture_inline(CaptureBuild &build) {
  Compiler c = build.compiler;
  List bridge = _func_bridge_binding(c, "func_from_capture");
  Array parameters = [], factory_values = [];
  foreach (Type field_type, build.field_types) {
    List parameter = c.sym.introduce(c.fresh_name("lambda_capture"));
    parameters.push(field_type.parameter_ast(parameter));
    factory_values.push(_func_bound(field_type, parameter));
  }
  List context = c.sym.introduce(c.fresh_name("lambda_context"));
  List storage = _capture_storage(
    build, context, factory_values.list_free());
  Macro factory = $capture_factory;
  List factory_body = c.rebuild_statement(
    factory(storage, _capture_construct(build, context)));
  List declaration_params = %(params @{parameters.list_free()});
  c.add_early(
    c.wrapper_function(
      %("Func"), bridge, declaration_params.cdr(), factory_body.cdr()));
  List parameter_types = build.field_types.list_free();
  Type factory_type = %((func $parameter_types) "Func");
  List call = _func_bridge_call(
    c, bridge, declaration_params, factory_type, build.values.list_free());
  return _capture_result(build, NULL, call);
}

static List _capture_plain(CaptureBuild &build) {
  Compiler c = build.compiler;
  List context = c.sym.introduce(c.fresh_name("lambda_context"));
  List storage = _capture_storage(build, context, build.values.list_free());
  return _capture_result(build, storage, _capture_construct(build, context));
}

static List _lower_captured_lambda(
  Compiler c, List entries, List captures, List body) {
  CaptureBuild build = {
    .compiler = c, .entries = entries, .body = body,
    .slots = {}, .fields = [], .field_types = [], .locals = [], .values = []
  };
  build.adapter = c.sym.introduce(c.fresh_name("lambda"));
  build.closure = c.sym.introduce(c.fresh_name("lambda_closure"));
  build.argv = c.sym.introduce(c.fresh_name("lambda_argv"));
  build.environment_name = c.fresh_name("lambda_context");
  build.environment_type_binding = c.sym.introduce(build.environment_name);
  build.value_type = %(${build.environment_name});
  build.pointer_type = %(* const ${build.environment_name});
  build.environment_local = c.sym.introduce(
    c.fresh_name("lambda_context_value"));
  c.semantic_binding_facts()[%(automatic ${build.environment_local})] = 1;
  c.semantic_binding_facts()[%(type ${build.environment_local})] =
    build.pointer_type;
  _capture_environment(build, captures);
  _capture_adapter(build);
  return c.inline_header ? _capture_inline(build) : _capture_plain(build);
}

/** The parameter types of a lambda's function signature, keeping typed
    declarators; a bare parameter is a `Var`. */
List Compiler.lambda_param_types(Compiler c, List entries) {
  if (!entries) return %((void));
  Array types = [];
  foreach (List entry, entries)
    match (entry) {
      case %(binding ? ?): types.push(%("Var"));
      case %(param ? ?): {
        Type type = entry.type_from_ast().declared();
        if (type.car() == <&> || type.car() == <opt-ref>)
          type = cons(
            type.car(), c.sym.normalize_declared_type(type.cdr()));
        types.push(type);
      }
    }
  return types.list_free();
}

/** Lowers a resolved lambda expression to emitter-ready helper references.
    `expression` must retain the resolved `expr`, `lambda`, `params`, and
    optional `captures` rows. A noncapturing lambda becomes a static
    `Var`-returning helper. A lambda with capture rows becomes a `FuncAdapter`
    helper and a `Func` whose copied context stores value snapshots and typed
    reference addresses; capture expressions run once from left to right.
    Nested lambdas lower inside out, block fallthrough and bare returns produce
    no value, and synthesized declarations enter the early queue. Parentheses
    remain around lowered helpers; other non-lambda expressions pass through.
*/
List Compiler.lower_lambda_expr(Compiler c, List expression) {
  if (expression.car() == <at> || expression.car() == <src>)
    return Ast.rewrite_children(
      expression, %!(List child) => c.lower_lambda_expr(child));
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  match (expression) {
    case %(expr ?type ${$source_content_pattern($grouped, %(?inner))}): {
      List lowered = c.lower_lambda_expr(inner);
      if (lowered == inner) return expression;
      Macro grouped = $grouped;
      return c.rebuild_expression(type, grouped(lowered));
    }
    case captured(?body, *captures, *entries):
      return _lower_captured_lambda(c, entries, captures, body);
    case lambda(?body, *params): {
      Type type = expression.cadr();
      /* Only a meta body leaves a noncapturing `Func` lambda unlifted. */
      if (type.match(%("Func"))) {
        Type signature = %(
          (func ${c.lambda_param_types(params)}) "Var");
        return c.lift_func_expression(
          c.rebuild_expression(signature, lambda(body, params)));
      }
      String lname = c.fresh_name("lambda");
      List lambda_binding = c.sym.introduce(lname);
      List decl_params = _params_to_decl_params(params);
      c.add_early(
        c.wrapper_function(
          %(static "Var"), lambda_binding, decl_params.cdr(),
          _helper_body(c, body, NULL).cdr()));
      return %(expr $type (ident $lambda_binding));
    }
  }
  return expression;
}
