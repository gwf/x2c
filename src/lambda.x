/*  lambda.x -- lambda transformation helpers for the x2c compiler

    Lowers lambda literals into static helper functions, with
    `Func` storage for
    lexical captures, and synthesizes adapters when a receiving function
    pointer differs from the canonical `Var`-based signature. Synthesized
    declarations enter the Compiler's early declaration queue.
*/

#pragma once
#include "compiler.x"
#pragma private

#include "type.x"
#include "expressions.x"
#include "string.x"
#include "symbol.x"
#include "var.x"
#include "list.x"

// Produce typed parameters from types and their binding identities.
static List _decl_params_from_types_with_names(List types, List names) {
  List params = types.zip_with(
    names,
    %!(Type type, List name) => type.parameter_ast(name));
  return %(params @params);
}

// Build fresh binding identities a0..aN.
static List _auto_names(Compiler compiler, int count) {
  Array out = %[];
  for (int index = 0; index < count; index++) {
    String pname = %"a$index";
    out.push(compiler.sym.introduce(pname));
  }
  List result = out.list_free();
  return result;
}

// Preserve typed declarators; bare lambda parameters remain Var.
static List _params_to_decl_params(List names) {
  if (!names) return %(params (param (void) (bind () ()))) ;
  Array out = %[];
  foreach(Var item, names)
    match (item) {
      case %(!set ?identity (binding ? ?)):
        out.push(%(param ("Var") (bind $identity ())));
      case %(param ? ?): out.push(item);
    }
  List params = out.list_free();
  return %(params @params);
}

static int _collect_param_types(List raw_params, List *out_types) {
  Array types = %[], int all_var = 1;
  foreach(Var entry, raw_params) {
    Var ptype = entry;
    match (entry)
      case %(param ? ?): ptype = entry.list().type_from_ast();
    List ptype_list = ptype is <list> ? ptype.list() : %( $ptype );
    types.push(ptype_list);
    if (all_var && ptype_list != %("Var")) all_var = 0;
  }
  List result = types.list_free();
  if (out_types) *out_types = result;
  return all_var;
}

// Split a direct or pointer function Type into fixed parameters and return.
static int _typed_function_parts(Type type, List *params, Type *return_type) {
  if (!type) return 0;
  type = type.canonicalize();
  if (type.is_pointer()) type = type.dereference();
  match (type)
    case %((func (*parameters)) ?return_head *return_tail): {
      List values = parameters;
      match (values)
        case %((!is ?only type <list>)): {
          Type parameter = only;
          if (parameter.canonicalize() === %(void)) values = NULL;
        }
      if (params) *params = values;
      if (return_type) *return_type = %($return_head @return_tail);
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
    : %"target signature: unresolved";
  String source_note = source
    ? %"source signature: ${source.repr()}"
    : %"source signature: unresolved";
  compiler.report_error(
    <type>, message, NULL,
    %($target_note $source_note @details));
}

// Permit matching parameter types and one dynamic extraction.
static int _typed_adapter_parameter_allowed(
  Compiler compiler, Type target, Type source) {
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

static List _callback_function(
  Compiler compiler, List binding, List parameters, Type result,
  List source_binding, Type source_type, List source_parameters) {
  List names = _auto_names(compiler, parameters.len());
  List declaration_params =
    _decl_params_from_types_with_names(parameters, names);
  Array arguments = %[];
  for (; parameters;
       parameters = parameters.cdr(),
       source_parameters = source_parameters.cdr(),
       names = names.cdr()) {
    List argument = %(expr ${parameters.car()} (ident ${names.car()}));
    arguments.push(
      compiler.convert_expression(argument, source_parameters.car()));
  }
  List call = %(expr ${source_type.apply().canonicalize()}
    (call (expr $source_type (ident $source_binding))
          (args @{arguments.list_free()})));
  List statement = result === %(void) ? call
    : %(return ${compiler.convert_expression(call, result)});
  return %(
    function (static $result)
      (bind $binding ((fnmod $declaration_params)))
      (block (stmnt $statement))
  );
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
      origin = at.integer();
    }
    case %(expr ?target (tadapt ?at (expr ?source ?))): {
      int old_origin = c.origin;
      c.origin = at.integer();
      defer c.origin = old_origin;
      Type target_type = c.sym.resolve_key(target);
      _typed_adapter_error(
        c,
        "typed callback adapter source must be a direct function",
          target_type, source,
        %("supported: a free function or Type.method designator"));
    }
    default: return expression;
  }
  int old_origin = c.origin;
  c.origin = origin;
  defer c.origin = old_origin;
  Type target_type = c.sym.resolve_key(target_spelling);
  if (!source_binding || !source_type || source_type.is_pointer() ||
      !source_type.is_function()) {
    _typed_adapter_error(
      c,
      "typed callback adapter source must be a direct function",
      target_type, source_type,
      %("supported: a free function or Type.method designator"));
  }
  List target_params = NULL, source_params = NULL;
  Type target_return = NULL, source_return = NULL;
  if (!_typed_function_parts(target_type, &target_params, &target_return)) {
    _typed_adapter_error(
      c, "typed callback adapter target is incomplete",
      target_type, source_type, NULL);
  }
  if (!_typed_function_parts(source_type, &source_params, &source_return)) {
    _typed_adapter_error(
      c, "typed callback adapter source is incomplete",
      target_type, source_type, NULL);
  }
  if (_typed_params_variadic(target_params) ||
      _typed_params_variadic(source_params)) {
    _typed_adapter_error(
      c, "typed callback adapter cannot be variadic",
      target_type, source_type, NULL);
  }
  int target_count = target_params.len(), source_count = source_params.len();
  if (target_count != source_count) {
    String detail =
      %"target has %d parameters; source has %d".printf(
        target_count, source_count);
    _typed_adapter_error(
      c, "typed callback adapter arity mismatch",
      target_type, source_type, %($detail));
  }
  target_return = target_return.canonicalize();
  source_return = source_return.canonicalize();
  if (target_return === %(void) || source_return === %(void)) {
    _typed_adapter_error(
      c, "typed callback adapter does not support void return",
      target_type, source_type, NULL);
  }
  if (target_return != source_return) {
    _typed_adapter_error(
      c, "typed callback adapter return type mismatch",
      target_type, source_type, NULL);
  }
  int index = 0;
  List targets = target_params, sources = source_params;
  for (; targets;
       targets = targets.cdr(), sources = sources.cdr(), index++) {
      Type target_param = targets.car();
      Type source_param = sources.car();
    if (!_typed_adapter_parameter_allowed(c, target_param, source_param)) {
      String detail =
        %"parameter %d: %s cannot adapt to %s".printf(
          index + 1, target_param.repr(), source_param.repr());
      _typed_adapter_error(
        c, "typed callback adapter parameter mismatch",
        target_type, source_type, %($detail));
    }
  }

  List key = %(tadapt $source_binding $target_type);
  Var stored;
  if (c.names.adapters.try_get(key, &stored))
    return %(expr $target_spelling (ident $stored));

  String adapter_name = c.fresh_name("callback_adapt");
  List adapter_binding = c.sym.introduce(adapter_name);
  List function = _callback_function(
    c, adapter_binding, target_params, target_return,
    source_binding, source_type, source_params);
  c.names.adapters[key] = adapter_binding;
  c.add_early(function);
  return %(expr $target_spelling (ident $adapter_binding));
}

static int _func_adapter_source(
  Type type, List payload, Type *source_type, List *source_binding) {
  match (payload) {
    case %(ident ?binding): {
      if (!type || type.is_pointer() || !type.is_function()) return 0;
      if (source_type) *source_type = type;
      if (source_binding) *source_binding = binding;
      return 1;
    }
    case %(cast ? (expr ?inner_type ?inner_payload)):
      return _func_adapter_source(
        inner_type, inner_payload,
        source_type, source_binding);
    case %(parens (expr ?inner_type ?inner_payload)):
      return _func_adapter_source(
        inner_type, inner_payload,
        source_type, source_binding);
    case %(op & (expr ?inner_type ?inner_payload)):
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
  return List.equal(compiler.sym.resolve_key(type), adapter);
}

/* A function already written in the adapter's own shape needs no wrapper:
   C converts the designator to a pointer at the call. */
static int _is_func_adapter_target(Compiler compiler, Type type) {
  if (!type) return 0;
  Type adapter = compiler.sym.resolve_key(%("FuncAdapter"));
  if (!adapter || !adapter.is_pointer()) return 0;
  Type pointee = adapter.dereference();
  return List.equal(type.canonicalize(), pointee.canonicalize());
}

static List _adapter_symbol_literal(Symbol value) =>
  %(expr ("Symbol") "${(unsigned long) value}");

static List _adapter_index_literal(int index) {
  String text = %"$index";
  return %(expr (int) (literal (int) $text));
}

static List _adapter_helper(Compiler compiler, String name, List *type) =>
  compiler.sym.resolve_global(%($name), type);

static List _type_literal(Compiler compiler, Type type) =>
  compiler.cache_literal_list(
    compiler.sym.normalize_declared_type(type));

static List _func_signature_literal(Compiler compiler, Type type) {
  List params = NULL;
  Type result = NULL;
  _typed_function_parts(type, &params, &result);
  Array normalized = %[];
  foreach (List parameter, params) {
    Type ptype = parameter.type().declared();
    if (ptype.car() == <&>)
      ptype = cons(
        <&>, compiler.sym.normalize_declared_type(ptype.cdr()));
    normalized.push(ptype);
  }
  List parameter_types = params ? normalized.list_free() : %((void));
  Type declared_result = result.declared();
  List signature = %((func $parameter_types) @declared_result);
  return compiler.cache_literal_list(signature);
}

static List _checked_func_argument(
  Compiler compiler, List adapter_type, Type parameter_type,
  List value_helper, Type value_helper_type,
  List reference_helper, Type reference_helper_type,
  List fn_binding, List argv_binding, int index, Type *storage_type) {
  if (parameter_type.car() == <&>) {
    Type target = parameter_type.cdr(), pointer = target.reference();
    List picked = %(
      expr (* void)
        (call (expr $reference_helper_type (ident $reference_helper))
              (args (expr ("Func") (ident $fn_binding))
                    (expr (* const "FuncArg") (ident $argv_binding))
                    ${_adapter_index_literal(index)}
                    ${_type_literal(compiler, target)}))
    );
    if (storage_type) *storage_type = pointer;
    return compiler.convert_expression(picked, pointer);
  }
  Symbol tag = compiler.sym.var_tag_for_type(parameter_type, NULL);
  if (!tag)
    _typed_adapter_error(
      compiler,
      "native binding parameter type has no Var representation",
      adapter_type, parameter_type, NULL);
  List picked = %(
    expr ("Var")
      (call (expr $value_helper_type (ident $value_helper))
            (args (expr ("Func") (ident $fn_binding))
                  (expr (* const "FuncArg") (ident $argv_binding))
                  ${_adapter_index_literal(index)}
                  ${_adapter_symbol_literal(tag)}))
  );
  if (storage_type) *storage_type = parameter_type;
  return compiler.convert_expression(picked, parameter_type);
}

/* Every generated native adapter has the runtime `FuncAdapter` ABI:
   `Var name(Func fn, const FuncArg *argv)`. It reads arguments into locals
   from index zero upward before calling the direct or context-bound target;
   C does not sequence call arguments, while these readers can raise. Error
   transfer through the generated C needs no landing pad. */
static List _build_func_adapter(
  Compiler c, Type diagnostic_type, Type source_type,
  List target, List supplied_fn_binding, List prefix) {
  List params = NULL, Type return_type = NULL;
  _typed_function_parts(source_type, &params, &return_type);
  if (_typed_params_variadic(params)) {
    Type func_type = c.sym.resolve_key(%("Func"));
    String message = List.equal(
      c.sym.resolve_key(diagnostic_type), func_type)
      ? "function conversion to Func cannot be variadic"
      : "native binding target cannot be variadic";
    _typed_adapter_error(
      c, message, diagnostic_type, source_type, NULL);
  }
  source_type = source_type.canonicalize();
  return_type = return_type.canonicalize();

  List value_type = NULL, reference_type = NULL, null_type = NULL;
  List value_helper = _adapter_helper(
    c, %"x2c_func_value_argument", &value_type);
  List reference_helper = _adapter_helper(
    c, %"x2c_func_reference_argument", &reference_type);
  List null_helper = _adapter_helper(c, %"Var_null", &null_type);
  if (!value_helper || !value_type ||
      !reference_helper || !reference_type ||
      !null_helper || !null_type) {
    _typed_adapter_error(
      c, "native binding needs Func argument readers from lib/func.x",
      diagnostic_type, source_type, NULL);
  }

  String name = c.fresh_name("func_adapt");
  List adapter_binding = c.sym.introduce(name);
  List fn_binding = supplied_fn_binding
                  ? supplied_fn_binding
                  : c.sym.introduce(c.fresh_name("func_binding"));
  List argv_binding = c.sym.introduce(c.fresh_name("func_argv"));
  List names = _auto_names(c, params.len());
  Array locals = %[], arguments = %[], int index = 0;
  // Each argument becomes a local: C fixes no evaluation order, and
  // argument readers raise, so index 0 must report before index 1.
  for (; params;
       params = params.cdr(), names = names.cdr(), index++) {
    Type ptype = params.car();
    List binding = names.car();
    Type storage_type = NULL;
    List value = _checked_func_argument(
      c, diagnostic_type, ptype,
      value_helper, value_type, reference_helper, reference_type,
      fn_binding, argv_binding, index, &storage_type);
    List (base, mods) = storage_type.declaration_parts();
    locals.push(
      %(declare $base (bindings (op = (bind $binding $mods) $value))));
    arguments.push(%(expr $ptype (ident $binding)));
  }
  List call = %(call $target (args @{arguments.list_free()}));
  List body = NULL;
  if (return_type === %(void)) {
    List null_call = %(
      expr ("Var") (call (expr $null_type (ident $null_helper)) (args)));
    body = %(@prefix @{locals.list_free()}
             (stmnt (expr $return_type $call))
             (stmnt (return $null_call)));
  }
  else {
    List boxed = c.convert_expression(%(expr $return_type $call), %("Var"));
    body = %(@prefix @{locals.list_free()} (stmnt (return $boxed)));
  }
  Type fn_type = %("Func"), argv_type = %(* const "FuncArg");
  List declaration_params = %(params
    ${fn_type.parameter_ast(fn_binding)}
    ${argv_type.parameter_ast(argv_binding)}
  );
  List function = %(
    function (static ("Var"))
      (bind $adapter_binding ((fnmod $declaration_params)))
      (block @body)
  );
  c.add_early(function);
  return adapter_binding;
}

static List _direct_func_adapter(
  Compiler compiler, Type diagnostic_type,
  List source_binding, Type source_type) {
  Type key_type = source_type.canonicalize();
  List key = %(fadapt $source_binding $key_type);
  Var stored;
  if (compiler.names.adapters.try_get(key, &stored)) return stored;
  List target = %(expr $source_type (ident $source_binding));
  List adapter = _build_func_adapter(
    compiler, diagnostic_type, source_type, target, NULL, NULL);
  compiler.names.adapters[key] = adapter;
  return adapter;
}

static int _direct_func_source(
  Type type, List payload, Type *source_type, List *source_binding) {
  match (payload) {
    case %(ident ?binding): {
      if (!type || type.is_pointer() || !type.is_function()) return 0;
      if (source_type) *source_type = type;
      if (source_binding) *source_binding = binding;
      return 1;
    }
    case %(parens (expr ?inner_type ?inner_payload)):
      return _direct_func_source(
          inner_type, inner_payload, source_type, source_binding);
    case %(op & (expr ?inner_type ?inner_payload)):
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
    arg_type, payload, &source_type, &source_binding)) {
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

static List _indirect_func_adapter(
  Compiler compiler, Type diagnostic_type, Type pointer_type,
  Type *out_context_type, List *out_context_field) {
  List key = %(findirect $pointer_type);
  Var stored;
  if (compiler.names.adapters.try_get(key, &stored)) {
    (List adapter, Type context, List field) = stored.list().cdr();
    if (out_context_type) *out_context_type = context;
    if (out_context_field) *out_context_field = field;
    return adapter;
  }

  String context_name = compiler.fresh_name("func_pointer_context");
  List context_binding = compiler.sym.introduce(context_name);
  List field_binding = compiler.sym.introduce(
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

  Type context_type = %($context_name);
  Type context_pointer = %(* const $context_name);
  List context_helper_type = NULL;
  List context_helper = _adapter_helper(
    compiler, %"Func_context", &context_helper_type);
  if (!context_helper || !context_helper_type) {
    _typed_adapter_error(
      compiler, "native binding needs Func.context from lib/func.x",
      diagnostic_type, pointer_type, NULL);
  }
  List fn_binding = compiler.sym.introduce(
    compiler.fresh_name("func_binding"));
  String field_name = binding_identity_spelling(field_binding);
  List context_value = %(
    expr (* const void)
      (call (expr $context_helper_type (ident $context_helper))
            (args (expr ("Func") (ident $fn_binding))))
  );
  List context_local = compiler.sym.introduce(
    compiler.fresh_name("func_pointer_context"));
  List context_declaration = %(
    declare (const $context_name)
      (bindings
        (op = (bind $context_local (*))
              (expr $context_pointer
                (cast $context_pointer $context_value))))
  );
  List context = %(expr $context_pointer (ident $context_local));
  List target = %(
    expr $pointer_type (op -> $context ($field_name))
  );
  List adapter = _build_func_adapter(
    compiler, diagnostic_type, pointer_type, target, fn_binding,
    %($context_declaration));
  compiler.names.adapters[key] = %(
    indirect-adapter $adapter $context_type $field_binding
  );
  if (out_context_type) *out_context_type = context_type;
  if (out_context_field) *out_context_field = field_binding;
  return adapter;
}

static List _direct_func_handle(
  Compiler compiler, List source_binding, Type source_type) {
  Type key_type = source_type.canonicalize();
  List key = %(fhandle $source_binding $key_type);
  Var stored;
  if (compiler.names.adapters.try_get(key, &stored))
    return %(expr ("Func") (ident ${stored.list()}));

  List adapter = _direct_func_adapter(
    compiler, %("Func"), source_binding, source_type);
  List signature = _func_signature_literal(compiler, source_type);
  List constructor_type = NULL;
  List constructor = _adapter_helper(
    compiler, %"Func_new", &constructor_type);
  if (!constructor || !constructor_type) {
    _typed_adapter_error(
      compiler, "function conversion needs Func.new from lib/func.x",
      %("Func"), source_type, NULL);
  }
  List handle = compiler.sym.introduce(
    compiler.fresh_name("func_handle"));
  List value = %(
    expr ("Func")
      (call (expr $constructor_type (ident $constructor))
            (args (expr ("FuncAdapter") (ident $adapter)) $signature))
  );
  compiler.add_early(
    %(
    declare (static "Func")
      (bindings (op = (bind $handle ()) $value))
  ));
  compiler.names.adapters[key] = handle;
  return %(expr ("Func") (ident $handle));
}

static List _func_bridge_binding(Compiler compiler, String stem) {
  String hash = %"%08x".printf(compiler.filename.hash());
  return compiler.sym.introduce(
    compiler.fresh_name(%"${stem}_$hash"));
}

static List _func_bridge_call(
  List bridge, List parameters, Type function_type, List arguments) {
  List prototype = %(
    declare (extern "Func")
      (bindings (bind $bridge ((fnmod $parameters))))
  );
  List call = %(
    expr ("Func")
      (call (expr $function_type (ident $bridge)) (args @arguments))
  );
  return %(
    expr ("Func") (parens (block $prototype (stmnt $call)))
  );
}

static List _direct_func_value(
  Compiler compiler, List source_binding, Type source_type) {
  List handle = _direct_func_handle(
    compiler, source_binding, source_type);
  if (!compiler.inline_header) return handle;

  Type key_type = source_type.canonicalize();
  List key = %(fgetter $source_binding $key_type);
  Var stored;
  List bridge = NULL;
  List parameters = %(params (param (void) (bind () ())));
  if (compiler.names.adapters.try_get(key, &stored)) bridge = stored;
  else {
    bridge = _func_bridge_binding(compiler, "func_get");
    compiler.add_early(
      %(
      function ("Func") (bind $bridge ((fnmod $parameters)))
        (block (stmnt (return $handle)))
    ));
    compiler.names.adapters[key] = bridge;
  }
  Type getter_type = %((func ((void))) "Func");
  return _func_bridge_call(
    bridge, parameters, getter_type, NULL);
}

static List _indirect_func_value(
  Compiler compiler, List expression, Type pointer_type) {
  Type context_type = NULL;
  List context_field = NULL;
  List adapter = _indirect_func_adapter(
    compiler, %("Func"), pointer_type,
    &context_type, &context_field);
  List signature = _func_signature_literal(compiler, pointer_type);
  List constructor_type = NULL;
  List constructor = _adapter_helper(
    compiler, %"Func_new_context", &constructor_type);
  if (!constructor || !constructor_type) {
    _typed_adapter_error(
      compiler,
      "function pointer conversion needs Func.new_context from lib/func.x",
      %("Func"), pointer_type, NULL);
  }

  List context = compiler.sym.introduce(
    compiler.fresh_name("func_pointer_context"));
  List context_value = %(
    expr $context_type
      (composite (commas $expression))
  );
  List declaration = %(
    declare $context_type
      (bindings (op = (bind $context ()) $context_value))
  );
  String field_name = binding_identity_spelling(context_field);
  List pointer = %(
    expr $pointer_type
      (op . (expr $context_type (ident $context)) ($field_name))
  );
  List address = %(
    expr ${context_type.reference()}
      (op & (expr $context_type (ident $context)))
  );
  List size = %(
    expr (size_t) (sizeof (expr $context_type (ident $context)))
  );
  List constructed = %(
    expr ("Func")
      (call (expr $constructor_type (ident $constructor))
            (args (expr ("FuncAdapter") (ident $adapter))
                  $signature $address $size))
  );
  List null_binding = compiler.sym.reference(%("NULL"), NULL);
  List result = %(
    expr ("Func")
      (op ? $pointer $constructed
            (expr ("Func") (ident $null_binding)))
  );
  return %(
    expr ("Func") (parens (block $declaration (stmnt $result)))
  );
}

static List _indirect_func_lift(
  Compiler compiler, List expression, Type pointer_type) {
  if (!compiler.inline_header)
    return _indirect_func_value(compiler, expression, pointer_type);

  Type key_type = pointer_type.canonicalize();
  List key = %(fpointer-factory $key_type);
  Var stored;
  List bridge = NULL;
  if (compiler.names.adapters.try_get(key, &stored)) bridge = stored;
  else {
    bridge = _func_bridge_binding(compiler, "func_from_pointer");
    List parameter = compiler.sym.introduce(
      compiler.fresh_name("func_pointer"));
    List parameters = %(
      params ${pointer_type.parameter_ast(parameter)}
    );
    List value = _indirect_func_value(
      compiler, %(expr $pointer_type (ident $parameter)), pointer_type);
    compiler.add_early(
      %(
      function ("Func") (bind $bridge ((fnmod $parameters)))
        (block (stmnt (return $value)))
    ));
    compiler.names.adapters[key] = bridge;
  }
  List parameters = %(
    params ${pointer_type.parameter_ast(NULL)}
  );
  Type factory_type = %((func ($pointer_type)) "Func");
  return _func_bridge_call(
    bridge, parameters, factory_type, %($expression));
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
      case %(parens (expr ? ?inner_payload)): {
        probe = inner_payload;
        unwrapped = 1;
      }
      case %(op & (expr ? ?inner_payload)): {
        probe = inner_payload;
        unwrapped = 1;
      }
    }
  }
  match (probe)
    case %(op * (expr ?operand_type ?)): {
      Type resolved = compiler.sym.resolve_key(operand_type.list());
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
List Compiler.lift_func_expression(Compiler compiler, List expression) {
  Type type = NULL;
  List payload = NULL;
  match (expression)
    case %(expr ?matched_type ?matched_payload): {
      type = matched_type;
      payload = matched_payload;
    }
  if (!type) return _deref_func_lift(compiler, expression, payload);
  Type func_type = compiler.sym.resolve_key(%("Func"));
  if (List.equal(compiler.sym.resolve_key(type), func_type)) return expression;

  match (payload)
    case %(lambda *): {
      expression = compiler.lower_lambda_expr(expression);
      match (expression)
        case %(expr ?lowered_type ?lowered_payload): {
          type = lowered_type;
          payload = lowered_payload;
        }
      if (List.equal(compiler.sym.resolve_key(type), func_type))
        return expression;
    }

  Type source_type = NULL;
  List source_binding = NULL;
  if (_direct_func_source(
        type, payload, &source_type, &source_binding))
    return _direct_func_value(compiler, source_binding, source_type);

  Type pointer_type = _func_pointer_value_type(compiler, type);
  if (pointer_type)
    return _indirect_func_lift(compiler, expression, pointer_type);
  Type resolved = compiler.sym.resolve_key(type);
  if (resolved && resolved.is_function()) {
    Type pointer = cons(<*>, resolved);
    return _indirect_func_lift(compiler, %(expr $pointer $payload), pointer);
  }
  return _deref_func_lift(compiler, expression, payload);
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
List Compiler.adapt_lambda_arg(
  Compiler compiler, List argument, List expected_type) {
  Type orig_type = NULL, List orig_binding = NULL;
  match (argument) {
    case %(expr ? (parens ?inner)): {
      List adapted = compiler.adapt_lambda_arg(inner, expected_type);
      if (adapted == inner) return argument;
      return %(expr $expected_type (parens $adapted));
    }
    case %(expr ?type (ident ?binding)): {
      orig_type = type;
      orig_binding = binding;
    }
    default: return argument;
  }
  if (!expected_type) return argument;

  Type expected = expected_type;
  expected = expected.canonicalize();
  if (!expected) expected = expected_type;
  List raw_params = NULL;
  Var return_type = void;
  match (expected) {
    case %((func (*parameters)) ?return_head *): {
      raw_params = parameters;
      return_type = return_head;
    }
    case %((!or (!quote *) & ^)
           (func (*parameters)) ?return_head *): {
      raw_params = parameters;
      return_type = return_head;
    }
    default: return argument;
  }
  if (_typed_params_variadic(raw_params)) return argument;

  List param_types = NULL;
  int all_params_var = _collect_param_types(raw_params, &param_types);
  List source_params = NULL, source_param_types = NULL;
  _typed_function_parts(orig_type, &source_params, NULL);
  _collect_param_types(source_params, &source_param_types);
  List return_type_list = return_type is <list>
    ? return_type.list() : %( $return_type );
  if (all_params_var && return_type_list === %("Var")) return argument;

  String adapter = compiler.fresh_name("lambda_adapt");
  List adapter_binding = compiler.sym.introduce(adapter);
  compiler.add_early(_callback_function(
    compiler, adapter_binding, param_types, return_type_list,
    orig_binding, orig_type, source_param_types));
  return %(expr $expected_type (ident $adapter_binding));
}

static Type _entry_type(Compiler compiler, List entry) {
  match (entry) {
    case %(binding ? ?): return %("Var");
    case %(param ? ?): {
      Type type = entry.type_from_ast().declared();
      if (type.car() == <&>)
        return cons(
          <&>, compiler.sym.normalize_declared_type(type.cdr()));
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
  Array types = %[];
  foreach (List entry, entries)
    types.push(_entry_type(compiler, entry));
  List parameter_types = entries ? types.list_free() : %((void));
  List signature = %((func $parameter_types) "Var");
  return compiler.cache_literal_list(signature);
}

static int _cell_parts(
  Map cells, List binding, List *cell, Type *type) {
  Var stored;
  if (!cells.try_get(binding, &stored)) return 0;
  match (stored)
    case %(lambda-cell ?matched_cell ?matched_type): {
      if (cell) *cell = matched_cell;
      if (type) *type = matched_type;
      return 1;
    }
  return 0;
}

static void _record_region_binding(
  Compiler compiler, List binding, Map owned, Array order) {
  if (!binding || owned.contains(binding)) return;
  Var automatic, stored_type;
  Map facts = compiler.semantic_binding_facts();
  if (!facts.try_get(%(automatic $binding), &automatic) ||
      !facts.try_get(%(type $binding), &stored_type))
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
  Array resume = %[];
  defer resume.free();
  for (;;) {
    int pruned = 0;
    match (ast) {
      case %(lambda *): pruned = 1;
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
    case %(expr ? (ident ?binding)): return binding;
    case %(expr ? (parens ?inner)):
      return _lvalue_binding(inner);
    case %(parens ?inner): return _lvalue_binding(inner);
    case %(expr ? (op . ?base *)):
      return _lvalue_binding(base);
    case %(op . ?base *): return _lvalue_binding(base);
    case %(expr ? (index (expr ((dim *) *) ?base) ?)):
      return _lvalue_binding(base);
  }
  return NULL;
}

static void _require_capture_lvalue(Compiler c, List target) {
  List binding = _lvalue_binding(target);
  if (binding && c.semantic_binding_facts().contains(
                   %(lambda-snapshot $binding)))
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
  Array pending = %[];
  defer pending.free();
  pending.push(ast);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node) {
      case %(lambda *): continue;
      case %(op & ?target): _require_capture_lvalue(c, target);
      case %(op ?operator ?target *):
        if (operator is <symbol> && ast_changes_left_operand(operator))
          _require_capture_lvalue(c, target);
      case %(postfix ? ?target): _require_capture_lvalue(c, target);
      case %(dstrasgn (targets *targets) ?):
        foreach (List target, targets) _require_capture_lvalue(c, target);
      case %(call (expr ?callee_type ?) (args *arguments)): {
        List parameters = NULL;
        if (_typed_function_parts(callee_type, &parameters, NULL))
          for (; parameters && arguments;
               parameters = parameters.cdr(), arguments = arguments.cdr()) {
            Type parameter = parameters.car();
            if (parameter.car() == <&>)
              _require_capture_lvalue(c, arguments.car());
          }
      }
    }
    foreach (Var child, node) pending.push(child);
  }
}

static void _collect_reference_captures(
  List ast, Map owned, Map candidates) {
  Array pending = %[];
  defer pending.free();
  pending.push(ast);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node)
      case %(capture ? (& *) (expr ? (op & ?target))): {
        List binding = _lvalue_binding(target);
        Var stored;
        if (binding && owned.try_get(binding, &stored)) {
          Type type = stored;
          if (type.car() != <&>) candidates[binding] = type;
        }
      }
    foreach (Var child, node) pending.push(child);
  }
}

static List _cell_reference(List cell, Type type) =>
  %(expr ${type.reference()} (ident $cell));

static List _cell_value(List cell, Type type) => %(
    expr $type
      (parens
        (expr $type (op * ${_cell_reference(cell, type)})))
  );

static List _rewrite_lambda_cells(
  Compiler compiler, List ast, Map cells);

static List _cell_declaration(
  Compiler compiler, List cell, Type type, List initializer) {
  Type pointer = type.reference();
  List allocator_type = NULL;
  String allocator_name = initializer ? "Scope_memdup" : "Scope_malloc";
  List allocator = _adapter_helper(
    compiler, allocator_name, &allocator_type);
  List (value_base, value_mods) = type.declaration_parts();
  List size = %(
    expr (size_t)
      (sizeof
        (parens
          (decl $value_base (bindings (bind () $value_mods)))))
  );
  List arguments = %($size);
  if (initializer) {
    List compound = NULL;
    match (initializer)
      case %(expr ? (composite ?)): compound = initializer;
    if (!compound)
      compound = %(
        expr () (composite (commas $initializer))
      );
    List value = %(expr $type (cast $type $compound));
    List address = %(expr $pointer (op & $value));
    List source = %(
      expr (* const void) (cast (* const void) $address)
    );
    arguments = %($source $size);
  }
  List allocation = %(
    expr (* void)
      (call (expr $allocator_type (ident $allocator))
            (args @arguments))
  );
  List (base, mods) = pointer.declaration_parts();
  return %(
    declare $base
      (bindings (op = (bind $cell $mods) $allocation))
  );
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
    has_cell |= binding && cells.contains(binding);
  }
  if (!has_cell) return NULL;

  Array sequence = %[];
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
    if (_cell_parts(cells, binding, &cell, &type)) {
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
    case %(expr ?source_type (ident ?binding)): {
      List cell = NULL;
      Type type = NULL;
      if (_cell_parts(cells, binding, &cell, &type)) {
        if (source_type.car() == <&>)
          return %(expr $source_type (ident $cell));
        return _cell_value(cell, type);
      }
      return ast;
    }
  }
  return Ast.rewrite_children(
    ast, %!(List child) => _rewrite_lambda_cells(compiler, child, cells));
}

static List _prepare_lambda_region(
  Compiler compiler, List entries, List body);

/* Nested bodies own their local cells; their construction expressions still
   execute in the enclosing region. Capture resolution has already assigned
   each binding its value or reference mode. */
static List _prepare_nested_lambda_regions(
  Compiler compiler, List ast) {
  if (!ast) return ast;
  match (ast) {
    case %(expr ?type
           (lambda (params *entries) (captures *captures) ?body)): {
      List prepared = _prepare_lambda_region(compiler, entries, body);
      return prepared == body ? ast : %(
        expr $type
          (lambda (params @entries) (captures @captures) $prepared)
      );
    }
    case %(expr ?type (lambda (params *entries) ?body)): {
      List prepared = _prepare_lambda_region(compiler, entries, body);
      return prepared == body ? ast
           : %(expr $type (lambda (params @entries) $prepared));
    }
  }
  return Ast.rewrite_children(
    ast, %!(List child) => ast_contains_head(child, <lambda>)
      ? _prepare_nested_lambda_regions(compiler, child) : child);
}

static List _parameter_setup(
  Compiler compiler, List entries, Map cells) {
  Array setup = %[];
  foreach (List entry, entries) {
    List binding = _entry_binding(entry);
    List cell = NULL;
    Type type = NULL;
    if (!_cell_parts(cells, binding, &cell, &type)) continue;
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
    case %(block *items): return %(block @setup @items);
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
   initializer order. Snapshot rows retain their separate binding identities. */
static List _prepare_lambda_region(
  Compiler compiler, List entries, List body) {
  if (!ast_contains_head(body, <lambda>)) return body;
  body = _prepare_nested_lambda_regions(compiler, body);
  Map owned = %{};
  Array order = %[];
  foreach (List entry, entries)
    _record_region_binding(
      compiler, _entry_binding(entry), owned, order);
  _collect_region_bindings(
    compiler, body, owned, order);

  Map candidates = %{};
  _collect_reference_captures(body, owned, candidates);
  if (!candidates.len()) return body;

  Map cells = %{};
  foreach (List binding, order) {
    Var stored_type;
    if (!candidates.try_get(binding, &stored_type)) continue;
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
List Compiler.prepare_lambda_cells(
  Compiler compiler, List declarator, List body) {
  List entries = NULL;
  match (declarator)
    case %(bind ? ((fnmod (params *parameters)))):
      entries = parameters;
  return _prepare_lambda_region(compiler, entries, body);
}

/* Rewrite capture-construction expressions through this environment, but do
   not enter a nested lambda body. Its own environment and lowering handle
   that body once the rewritten capture values are available. */
static List _rewrite_lambda_captures(
  Compiler compiler, List ast, Map slots, List environment_binding,
  Type environment_type) {
  if (!ast) return ast;
  match (ast) {
    case %(lambda ?parameters (!set ?rows (captures *)) ?body): {
      List rewritten = Ast.rewrite_children(rows, %!(List record) => {
        match (record)
          case %(capture ?binding ?type ?expression): {
            List value = _rewrite_lambda_captures(
              compiler, expression, slots, environment_binding,
              environment_type);
            if (value != expression)
              return %(capture $binding $type $value);
          }
        return record;
      });
      return rewritten == rows ? ast
           : %(lambda $parameters $rewritten $body);
    }
    case %(lambda ? ?): return ast;
    case %(expr ?source_type (ident ?bound)): {
      Var stored;
      if (slots.try_get(bound, &stored)) {
        List field = NULL;
        Type storage_type = NULL;
        match (stored)
          case %(capture-field ?matched_field ?matched_type): {
            field = matched_field;
            storage_type = matched_type;
          }
        String field_name = binding_identity_spelling(field);
        List read = %(
          expr $storage_type
            (op -> (expr $environment_type (ident $environment_binding))
                   ($field_name))
        );
        if (source_type.car() == <&>)
          return %(expr $source_type ${read.caddr()});
        List converted = compiler.convert_expression(read, source_type);
        match (converted)
          case %(expr ? (call "Var_pointer" ?)):
            return %(expr $source_type
                     (parens (expr $source_type
                       (cast $source_type $converted))));
        return converted;
      }
      return ast;
    }
  }
  return Ast.rewrite_children(
    ast, %!(List child) => _rewrite_lambda_captures(
      compiler, child, slots, environment_binding, environment_type));
}

static List _lower_nested_lambdas(Compiler compiler, List ast) {
  if (!ast) return ast;
  match (ast) {
    case %(expr ?type
           (lambda ?parameters (captures *captures) ?body)): {
      List lowered_body = _lower_nested_lambdas(compiler, body);
      List nested = %(
        expr $type
          (lambda $parameters (captures @captures) $lowered_body)
      );
      return compiler.lower_lambda_expr(nested);
    }
    case %(expr ?type (lambda ?parameters ?body)): {
      List lowered_body = _lower_nested_lambdas(compiler, body);
      List nested = %(expr $type (lambda $parameters $lowered_body));
      return compiler.lower_lambda_expr(nested);
    }
  }
  return Ast.rewrite_children(
    ast, %!(List child) => _lower_nested_lambdas(compiler, child));
}

static List _null_return(void) => %(
    return ("Var") (expr ("Var") (call "Var_null" (args)))
  );

/* A block lambda returns Null for a bare return and for
   fallthrough. Nested lambdas normalize their own returns when lowered. */
static List _block_returns(List ast) {
  if (!ast) return ast;
  match (ast) {
    case %(lambda *): return ast;
    case %(return): return _null_return();
  }
  return Ast.rewrite_children(ast, _block_returns);
}

static List _helper_body(
  Compiler compiler, List body, List setup) {
  match (body) {
    case %(block *items): {
      List normalized = _block_returns(items);
      return %(block @setup @normalized ${_null_return()});
    }
    case %(expr (void) ?):
      return %(block @setup (stmnt $body) ${_null_return()});
  }
  List result = compiler.convert_expression(body, %("Var"));
  return %(block @setup (stmnt (return $result)));
}

static List _captured_context_call(
  Type type, List context, List adapter, Type adapter_type, List signature,
  List constructor, Type constructor_type) {
  List address = %(expr ${type.reference()}
    (op & (expr $type (ident $context))));
  List size = %(expr (size_t) (sizeof (expr $type (ident $context))));
  return %(expr ("Func")
    (call (expr $constructor_type (ident $constructor))
          (args (expr $adapter_type (ident $adapter))
                $signature $address $size)));
}

/* Capture rows arrive resolved and in first-use order from `literals.x`.
   Materialize one local per row before the
   context aggregate so conversion effects run left to right. `Var` fields are
   value snapshots; reference fields keep cell or caller addresses without
   extending their lifetime. `Func.new_context` copies the aggregate into the
   current Scope, and the emitted helper borrows it through the `FuncAdapter`
   ABI for each call. */
static List _lower_captured_lambda(
  Compiler compiler, List entries, List captures, List body) {
  String lname = compiler.fresh_name("lambda");
  List lambda_binding = compiler.sym.introduce(lname);
  List closure_binding = compiler.sym.introduce(
    compiler.fresh_name("lambda_closure"));
  List argv_binding = compiler.sym.introduce(
    compiler.fresh_name("lambda_argv"));
  String environment_name = compiler.fresh_name("lambda_context");
  List environment_typedef = compiler.sym.introduce(environment_name);
  Type environment_value_type = %($environment_name);
  Type environment_pointer_type = %(* const $environment_name);
  List environment_local = compiler.sym.introduce(
    compiler.fresh_name("lambda_context_value"));
  compiler.semantic_binding_facts()[%(automatic $environment_local)] = 1;
  compiler.semantic_binding_facts()[%(type $environment_local)] =
    environment_pointer_type;

  Map slots = %{};
  Array fields = %[], field_types = %[];
  Array capture_locals = %[], field_values = %[];
  foreach (List capture, captures)
    match (capture)
      case %(capture ?binding ?captured_type ?expression): {
        Type source_type = captured_type;
        Type storage_type = source_type.car() == <&>
                          ? source_type.cdr().type().reference()
                          : %("Var");
        List field = compiler.sym.introduce(
          compiler.fresh_name("lambda_capture"));
        List (field_base, field_mods) = storage_type.declaration_parts();
        fields.push(
          %(declare $field_base (bindings (bind $field $field_mods))));
        field_types.push(storage_type);
        slots[binding] = %(capture-field $field $storage_type);

        List temporary = compiler.sym.introduce(
          compiler.fresh_name("lambda_capture_value"));
        List value = compiler.convert_expression(
          expression, storage_type);
        List (base, mods) = storage_type.declaration_parts();
        capture_locals.push(
          %(
          declare $base
            (bindings (op = (bind $temporary $mods) $value))
        ));
        field_values.push(%(expr $storage_type (ident $temporary)));
      }
  compiler.add_early(
    %(
    typedef (struct $environment_name (fields @{fields.list_free()}))
            (bindings (bind $environment_typedef ()))
  ));

  List value_type = NULL, reference_type = NULL;
  List value_helper = _adapter_helper(
    compiler, %"x2c_func_value_argument", &value_type);
  List reference_helper = _adapter_helper(
    compiler, %"x2c_func_reference_argument", &reference_type);
  List context_type = NULL, constructor_type = NULL;
  List context_helper = _adapter_helper(
    compiler, %"Func_context", &context_type);
  List constructor = _adapter_helper(
    compiler, %"Func_new_context", &constructor_type);
  Type adapter_type = compiler.sym.resolve_key(%("FuncAdapter"));
  Array locals = %[];
  int index = 0;
  foreach (Var entry, entries) {
    Type parameter_type = _entry_type(compiler, entry);
    List binding = _entry_binding(entry);
    Type storage_type = NULL;
    List value = _checked_func_argument(
      compiler, adapter_type, parameter_type,
      value_helper, value_type, reference_helper, reference_type,
      closure_binding, argv_binding, index++, &storage_type);
    List (base, mods) = storage_type.declaration_parts();
    locals.push(
      %(
      declare $base
        (bindings (op = (bind $binding $mods) $value))
      ));
  }
  List context_call = %(
    expr (* const void)
      (call (expr $context_type (ident $context_helper))
            (args (expr ("Func") (ident $closure_binding))))
  );
  locals.push(
    %(
    declare (const $environment_name)
      (bindings
        (op = (bind $environment_local (*))
              (expr $environment_pointer_type
                (cast $environment_pointer_type $context_call))))
  ));
  body = _lower_nested_lambdas(compiler, body);
  List rewritten = _rewrite_lambda_captures(
    compiler, body, slots, environment_local, environment_pointer_type);
  Type fn_type = %("Func"), argv_type = %(* const "FuncArg");
  List declaration_params = %(params
    ${fn_type.parameter_ast(closure_binding)}
    ${argv_type.parameter_ast(argv_binding)}
  );
  compiler.add_early(
    %(
    function (static ("Var"))
      (bind $lambda_binding ((fnmod $declaration_params)))
      ${_helper_body(compiler, rewritten, locals.list_free())}
  ));

  List signature = _signature(compiler, entries);
  if (compiler.inline_header) {
    List bridge = _func_bridge_binding(compiler, "func_from_capture");
    Array parameters = %[], factory_values = %[];
    foreach (Type field_type, field_types) {
      List parameter = compiler.sym.introduce(
        compiler.fresh_name("lambda_capture"));
      parameters.push(field_type.parameter_ast(parameter));
      factory_values.push(%(expr $field_type (ident $parameter)));
    }
    List factory_context = compiler.sym.introduce(
      compiler.fresh_name("lambda_context"));
    List factory_storage = %(
      declare $environment_value_type
        (bindings
          (op = (bind $factory_context ())
                (expr $environment_value_type
                  (composite
                    (commas @{factory_values.list_free()})))))
    );
    List factory_construction = _captured_context_call(
      environment_value_type, factory_context, lambda_binding,
      adapter_type, signature, constructor, constructor_type);
    List declaration_params = %(params @{parameters.list_free()});
    compiler.add_early(
      %(
      function ("Func") (bind $bridge ((fnmod $declaration_params)))
        (block $factory_storage
               (stmnt (return $factory_construction)))
    ));
    List parameter_types = field_types.list_free();
    Type factory_type = %((func $parameter_types) "Func");
    List call = _func_bridge_call(
      bridge, declaration_params, factory_type,
      field_values.list_free());
    return %(
      expr ("Func")
        (parens
          (block @{capture_locals.list_free()} (stmnt $call)))
    );
  }
  List context_value = compiler.sym.introduce(
    compiler.fresh_name("lambda_context"));
  List context_storage = %(
    declare $environment_value_type
      (bindings
        (op = (bind $context_value ())
              (expr $environment_value_type
                (composite (commas @{field_values.list_free()})))))
  );
  List construction = _captured_context_call(
    environment_value_type, context_value, lambda_binding,
    adapter_type, signature, constructor, constructor_type);
  return %(
    expr ("Func")
      (parens
        (block @{capture_locals.list_free()} $context_storage
               (stmnt $construction)))
  );
}

/** Lowers a resolved lambda expression to emitter-ready helper references.
    `expression` must retain the resolved `expr`, `lambda`, `params`, and
    optional `captures` rows. A noncapturing lambda becomes a static
    `Var`-returning helper. A lambda with capture rows becomes a `FuncAdapter`
    helper and a `Func` whose copied context stores value snapshots and typed
    reference addresses; capture expressions run once from left to right.
    Nested lambdas lower inside out, block fallthrough and bare returns produce
    Null, and synthesized declarations enter the early queue. Parentheses
    remain around lowered helpers; other non-lambda expressions pass through.
*/
List Compiler.lower_lambda_expr(Compiler compiler, List expression) {
  match (expression) {
    case %(expr ?type (parens ?inner)): {
      List lowered = compiler.lower_lambda_expr(inner);
      if (lowered == inner) return expression;
      return %(expr $type (parens $lowered));
    }
    case %(expr ("Func")
           (lambda (params *entries) (captures *captures) ?body)):
      return _lower_captured_lambda(compiler, entries, captures, body);
    case %(expr ?type (lambda (params *entries) ?body)): {
      String lname = compiler.fresh_name("lambda");
      List lambda_binding = compiler.sym.introduce(lname);
      List decl_params = _params_to_decl_params(entries);
      compiler.add_early(
        %(
        function (static ("Var"))
          (bind $lambda_binding ((fnmod $decl_params)))
          ${_helper_body(compiler, body, NULL)}
      ));
      return %(expr $type (ident $lambda_binding));
    }
  }
  return expression;
}
