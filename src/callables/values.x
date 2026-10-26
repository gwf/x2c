/*  values.x -- direct and pointer-backed Func values */

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

  if (expression ~= $lambda_expression(?, *)) {
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
module int _direct_func_source(
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
      $fail.callable_shared(c, source_type);
    handle = c.sym.introduce(c.fresh_name("func_handle"));
    List value = _func_call(
      c, %("Func"), _func_bound(constructor_type, constructor),
      $(_func_bound(%("FuncAdapter"), adapter), signature));
    c.add_early(
      c.rebuild_statement($!{ static Func $handle = $value; }).cadr());
  }
  return _func_bound(%("Func"), handle);
}

static List _func_bridge_binding(Compiler c, String stem) {
  String hash = "%08x".printf(c.filename.hash());
  return c.sym.introduce(c.fresh_name(%"$(stem)_$hash"));
}

static List _func_bridge_call(
  Compiler c, List bridge, List parameters,
  Type function_type, List arguments) {
  List call = _func_call(
    c, %("Func"), _func_bound(function_type, bridge), arguments);
  /* A call through a bridge function the unit declares where it calls. */
  return $!Func{ ({
    extern Func $bridge(@(parameters.cdr()));
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
      params $(pointer_type.parameter_ast(parameter))
    );
    List value = _indirect_func_value(
      c, _func_bound(pointer_type, parameter), pointer_type);
    c.add_early(
      c.wrapper_function(
        %("Func"), bridge, parameters.cdr(),
        _func_return_body(c, value)));
  }
  List parameters = %(
    params $(pointer_type.parameter_ast(NULL))
  );
  Type factory_type = %((func ($pointer_type)) "Func");
  return _func_bridge_call(
    c, bridge, parameters, factory_type, $(expression));
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
    $fail.callable_context(c, pointer_type);

  List context = c.sym.introduce(c.fresh_name("func_pointer_context"));
  List declaration = _func_context_declaration(
    c, context_type, context, expression);
  String field_name = Ast.binding_spelling(context_field);
  List pointer = %(
    expr $pointer_type
      (op . $(_func_bound(context_type, context)) ($field_name)));
  List constructed = _func_context_call(
    c, context_type, context, _func_bound(%("FuncAdapter"), adapter),
    signature, _func_bound(constructor_type, constructor));
  return $!Func{ ({
    $declaration $(_func_present_statement(c, pointer, constructed))
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
  Type context_type = $(context_name);
  Type context_pointer = %(* const $context_name);
  Type context_helper_type = NULL;
  if (!_adapter_helper(c, "Func_context", context_helper_type) ||
      !context_helper_type)
    $fail.callable_native_context(c, diagnostic_type, pointer_type);
  List fn_binding = c.sym.introduce(c.fresh_name("func_binding"));
  List context_local = c.sym.introduce(c.fresh_name("func_pointer_context"));
  List context_declaration = _context_local(
    c, context_type, context_local, fn_binding);
  String field_name = Ast.binding_spelling(field_binding);
  List context = _func_bound(context_pointer, context_local);
  List target = $!($pointer_type){ $context->$field_name };
  List adapter = _build_func_adapter(
    c, diagnostic_type, pointer_type, target, fn_binding,
    $(context_declaration), NULL);
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
    $(_func_bound(%("Func"), fn)));
  List cast = %(expr $pointer (cast $pointer $call));
  return c.rebuild_statement($!{ $pointer $local = $cast; }).cadr();
}

static void _func_pointer_context(
  Compiler c, Type pointer_type, String &context_name,
  List &field_binding) {
  context_name = c.fresh_name("func_pointer_context");
  List context_binding = c.sym.introduce(context_name);
  field_binding = c.sym.introduce(c.fresh_name("func_pointer"));
  List field = c.rebuild_statement($!{ $pointer_type $field_binding; }).cadr();
  c.add_early(c.capture_environment(context_binding, $(field)));
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
    c, %("Func"), constructor, $(adapter, signature, address, size));
}

static List _func_present_statement(
  Compiler c, List pointer, List constructed) {
  List null_binding = c.sym.reference(%("NULL"), NULL);
  List result = $!Func{
    $pointer ? $constructed : $(_func_bound(%("Func"), null_binding)) };
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

static List _func_signature_literal(Compiler c, Type type) =>
  c.cache_literal_list(c.func_signature(type));

static List _func_return_body(Compiler c, List value) {
  Macro shape = $return_value;
  return c.rebuild_statement(shape(value)).cdr();
}
