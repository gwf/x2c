/*  transform.x -- x2c AST transformation pipeline

    Lowers typed expressions, literals, and control flow into the AST forms
    consumed by C emission.

    One recursive normalizer owns expressions, lambda synthesis, and cleanup.
    Newly constructed nodes normalize locally; complete functions receive
    their transfer cleanup before emission. The active Compiler reports errors.
*/

#pragma once

/* CPP ignores pragma once in its main input. Define the cycle guard only
   during symbol preprocessing, so generated C keeps its declarations. */
#ifndef X2C_TRANSFORM_SOURCE
#ifdef X2CCPP
#define X2C_TRANSFORM_SOURCE
#endif

$(import "../lib/error-macros.xmacro")
#include "compiler.x"
#pragma private

$(import "../src/ast-rewrite.xmacro")
$(import "../src/adapter-memo.xmacro")

#include <stdio.h>

#include "ast.x"
#include "type.x"
#include "parse.x"
#include "expressions.x"
#include "string.x"
#include "symbol.x"
#include "var.x"
#include "list.x"
#include "protocol.x"
#include "regions.x"
#include "meta.x"

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

static List _callback_function(
  Compiler compiler, List binding, List parameters, Type result,
  List source_binding, Type source_type, List source_parameters) {
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
  List call = %(expr ${source_type.apply().canonicalize()}
    (call (expr $source_type (ident $source_binding))
          (args @{arguments.list_free()})));
  List statement = result === %(void) ? call
    : %(return ${compiler.convert_expression(call, result)});
  return compiler.wrapper_function(
    %(static @result), binding, declaration_params.cdr(),
    %((stmnt $statement)));
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
    if (!_typed_function_parts(target_type, target_params, target_return))
      _typed_adapter_error(
        c, "typed callback adapter target is incomplete",
        target_type, source_type, NULL);
    if (!_typed_function_parts(source_type, source_params, source_return))
      _typed_adapter_error(
        c, "typed callback adapter source is incomplete",
        target_type, source_type, NULL);
    if (_typed_params_variadic(target_params) ||
        _typed_params_variadic(source_params)) {
      _typed_adapter_error(
        c, "typed callback adapter cannot be variadic",
        target_type, source_type, NULL);
    }
    int target_count = target_params.len(), source_count = source_params.len();
    if (target_count != source_count) {
      String detail =
        "target has %d parameters; source has %d".printf(
          target_count, source_count);
      _typed_adapter_error(
        c, "typed callback adapter arity mismatch",
        target_type, source_type, %($detail));
    }
    target_return = target_return.canonicalize();
    source_return = source_return.canonicalize();
    if (target_return === %(void) || source_return === %(void))
      _typed_adapter_error(
        c, "typed callback adapter does not support void return",
        target_type, source_type, NULL);
    if (target_return != source_return)
      _typed_adapter_error(
        c, "typed callback adapter return type mismatch",
        target_type, source_type, NULL);
    int index = 0;
    List targets = target_params, sources = source_params;
    for (; targets;
         targets = targets.cdr(), sources = sources.cdr(), index++) {
      Type target_param = targets.car();
      Type source_param = sources.car();
      if (!_typed_param_allowed(c, target_param, source_param)) {
        String detail =
          "parameter %d: %s cannot adapt to %s".printf(
            index + 1, target_param.repr(), source_param.repr());
        _typed_adapter_error(
          c, "typed callback adapter parameter mismatch",
          target_type, source_type, %($detail));
      }
    }

    List key = %(tadapt $source_binding $target_type);
    List adapter_binding = NULL;
    $adapter.memo(c, key, adapter_binding) {
      String adapter_name = c.fresh_name("callback_adapt");
      adapter_binding = c.sym.introduce(adapter_name);
      List function = _callback_function(
        c, adapter_binding, target_params, target_return,
        source_binding, source_type, source_params);
      c.semantic_binding_facts()[%(function $adapter_binding)] = 1;
      c.add_early(function);
    }
    return %(expr $target_spelling (ident $adapter_binding));
  }
}

static int _func_adapter_source(
  Type type, List payload, Type &source_type, List &source_binding) {
  match (payload) {
    case %(ident ?binding): {
      if (!type || type.is_pointer() || !type.is_function()) return 0;
      source_type = type;
      source_binding = binding;
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

static List _checked_func_argument(
  Compiler compiler, List adapter_type, Type parameter_type,
  List value_helper, Type value_helper_type,
  List reference_helper, Type reference_helper_type,
  List fn_binding, List argv_binding, int index, Type &storage_type) {
  if (parameter_type.car() == <&> ||
      parameter_type.car() == <opt-ref>) {
    Type target = parameter_type.cdr(), pointer = target.reference();
    List picked = %(
      expr (* void)
        (call (expr $reference_helper_type (ident $reference_helper))
              (args (expr ("Func") (ident $fn_binding))
                    (expr (* const "FuncArg") (ident $argv_binding))
                    ${_integer_expression(index)}
                    ${compiler.cache_literal_list(target)}
                    ${_type_literal(compiler, target)}))
    );
    storage_type = pointer;
    return compiler.convert_expression(picked, pointer);
  }
  Symbol tag = compiler.sym.var_tag_for_type(parameter_type, NULL);
  Type resolved = compiler.sym.resolve_key(parameter_type);
  if (!tag && resolved &&
      (resolved.is_pointer() || resolved.car() == <struct>)) {
    /* A pointer with no Var tag of its own arrives as `<p48>`, and so does
       a record passed by value, as the address of its bytes. */
    Type pointer_type = NULL;
    List pointer_helper = _adapter_helper(
      compiler, "x2c_func_pointer_argument", pointer_type);
    List picked = %(
      expr (* void)
        (call (expr $pointer_type (ident $pointer_helper))
              (args (expr ("Func") (ident $fn_binding))
                    (expr (* const "FuncArg") (ident $argv_binding))
                    ${_integer_expression(index)}))
    );
    storage_type = parameter_type;
    if (resolved.is_pointer())
      return compiler.convert_expression(picked, parameter_type);
    Symbol star = <"*">;
    Type record_pointer = parameter_type.reference();
    return %(expr $parameter_type
               (op $star (expr $record_pointer
                           (cast $record_pointer $picked))));
  }
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
                  ${_integer_expression(index)}
                  ${_adapter_symbol_literal(tag)}))
  );
  storage_type = parameter_type;
  return compiler.convert_expression(picked, parameter_type);
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
  Array locals = [];
  int index = 0;
  foreach (Type type, types) {
    List binding = names.car();
    names = names.cdr();
    Type storage_type = NULL;
    List value = _checked_func_argument(
      compiler, diagnostic_type, type,
      value_helper, value_type, reference_helper, reference_type,
      fn_binding, argv_binding, index++, storage_type);
    List (base, mods) = storage_type.declaration_parts();
    locals.push(
      %(declare $base (bindings (op = (bind $binding $mods) $value))));
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
  compiler.add_early(compiler.wrapper_function(
    %(static "Var"), binding, parameters.cdr(),
    _helper_body(compiler, body, setup).cdr()));
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
  List call = %(expr $return_type (call $target (args @arguments)));
  Type resolved_result = c.sym.resolve_key(return_type);
  if (resolved_result && resolved_result.car() == <struct>) {
    /* A record result is returned as `<p48>` to a copy of its bytes. */
    Type result_type = NULL;
    List result_helper = _adapter_helper(
      c, "x2c_func_record_result", result_type);
    List result = c.sym.introduce(c.fresh_name("func_record"));
    List (base, mods) = return_type.declaration_parts();
    List address = %(expr ${return_type.reference()}
                         (op & (expr $return_type (ident $result))));
    call = %(block
      (declare $base (bindings (op = (bind $result $mods) $call)))
      (stmnt (return
        (expr ("Var")
          (call (expr $result_type (ident $result_helper))
                (args $address
                      (expr (unsigned long)
                        (sizeof (expr $return_type (ident $result))))))))));
  }
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
    case %(ident ?binding): {
      if (!type || type.is_pointer() || !type.is_function()) return 0;
      source_type = type;
      source_binding = binding;
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

static List _build_indirect_func_adapter(
  Compiler compiler, Type diagnostic_type, Type pointer_type,
  List key) {
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
  Type context_helper_type = NULL;
  List context_helper = _adapter_helper(
    compiler, "Func_context", context_helper_type);
  if (!context_helper || !context_helper_type)
    _typed_adapter_error(
      compiler, "native binding needs Func.context from lib/func.x",
      diagnostic_type, pointer_type, NULL);
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
  return %(indirect-adapter $adapter $context_type $field_binding);
}

static List _indirect_func_adapter(
  Compiler compiler, Type diagnostic_type, Type pointer_type,
  Type &out_context_type, List &out_context_field) {
  List key = %(findirect $pointer_type), result = NULL;
  $adapter.memo(compiler, key, result) {
    result = _build_indirect_func_adapter(
      compiler, diagnostic_type, pointer_type, key);
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
  }
  return %(expr ("Func") (ident $handle));
}

static List _func_bridge_binding(Compiler compiler, String stem) {
  String hash = "%08x".printf(compiler.filename.hash());
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
  List bridge = NULL;
  List parameters = %(params (param (void) (bind () ())));
  $adapter.memo(compiler, key, bridge) {
    bridge = _func_bridge_binding(compiler, "func_get");
    compiler.add_early(
      %(
      function ("Func") (bind $bridge ((fnmod $parameters)))
        (block (stmnt (return $handle)))
    ));
  }
  Type getter_type = %((func ((void))) "Func");
  return _func_bridge_call(
    bridge, parameters, getter_type, NULL);
}

static List _func_context_call(
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
  List constructed = _func_context_call(
    context_type, context, adapter, %("FuncAdapter"), signature,
    constructor, constructor_type);
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
  List bridge = NULL;
  $adapter.memo(compiler, key, bridge) {
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

  match (payload)
    case %(lambda *): {
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
    case %(expr ? (parens ?inner)): {
      List adapted = c.adapt_lambda_arg(inner, expected_type);
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
  int all_params_var = _collect_param_types(raw_params, param_types);
  List source_params = NULL, source_param_types = NULL;
  _typed_function_parts(orig_type, source_params, NULL);
  _collect_param_types(source_params, source_param_types);
  List return_type_list = return_type is <list>
    ? return_type : %( $return_type );
  if (all_params_var && return_type_list === %("Var")) return argument;

  String adapter = c.fresh_name("lambda_adapt");
  List adapter_binding = c.sym.introduce(adapter);
  List callback = _callback_function(
    c, adapter_binding, param_types, return_type_list,
    orig_binding, orig_type, source_param_types);
  c.add_early(callback);
  return %(expr $expected_type (ident $adapter_binding));
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
  Array types = [];
  foreach (List entry, entries)
    types.push(_entry_type(compiler, entry));
  List parameter_types = entries ? types.list_free() : %((void));
  List signature = %((func $parameter_types) "Var");
  return compiler.cache_literal_list(signature);
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
  Array pending = $auto([]);
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
   from its initializer or left for a later assignment. A braced
   initializer is already the compound literal's body. */
macro open Statement $compiler_cell(Type $type, Name $cell, Expr $value) {
  $type *$cell = Scope_memdup((const void *)&($type){$value}, sizeof($type));
}

macro open Statement $compiler_braced_cell(Type $type, Name $cell,
    Expr $compound) {
  $type *$cell = Scope_memdup((const void *)&($type)$compound,
                              sizeof($type));
}

macro open Statement $compiler_empty_cell(Type $type, Name $cell) {
  $type *$cell = Scope_malloc(sizeof($type));
}

macro open Expression $compiler_cell_value(Name $cell) => (*$cell);

static List _cell_declaration(
  Compiler c, List cell, Type type, List initializer) {
  Macro shape = $compiler_empty_cell;
  if (!initializer)
    return c.bind_syntax(shape(type, cell), AST_BLOCK, NULL);
  shape = $compiler_cell;
  match (initializer)
    case %(expr ? (composite ?)): shape = $compiler_braced_cell;
  List value = %(code-value "bound" $initializer ());
  return c.bind_syntax(shape(type, cell, value), AST_BLOCK, NULL);
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
    case %(expr ?source_type (ident ?binding)): {
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
      if (slots.try_get(bound, stored)) {
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

static List _no_value_return(void) => %(
    return ("Var") (expr ("Var") (literal ("Var") "void"))
  );

/* A block lambda returns void for a bare return and for
   fallthrough. Nested lambdas normalize their own returns when lowered. */
static List _block_returns(List ast) {
  if (!ast) return ast;
  match (ast) {
    case %(lambda *): return ast;
    case %(return): return _no_value_return();
  }
  return Ast.rewrite_children(ast, _block_returns);
}

static List _helper_body(
  Compiler compiler, List body, List setup) {
  match (body) {
    case %(block *items): {
      List normalized = _block_returns(items);
      return %(block @setup @normalized ${_no_value_return()});
    }
    case %(expr (void) ?):
      return %(block @setup (stmnt $body) ${_no_value_return()});
  }
  List result = compiler.convert_expression(body, %("Var"));
  return %(block @setup (stmnt (return $result)));
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

  Map slots = {};
  Array fields = [], field_types = [];
  Array capture_locals = [], field_values = [];
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

  Type context_type = NULL, constructor_type = NULL;
  List context_helper = _adapter_helper(
    compiler, "Func_context", context_type);
  List constructor = _adapter_helper(
    compiler, "Func_new_context", constructor_type);
  Type adapter_type = compiler.sym.resolve_key(%("FuncAdapter"));
  List types = entries.map(
    %!(List entry) => _entry_type(compiler, entry));
  List names = entries.map(_entry_binding);
  List locals = _func_argument_locals(
    compiler, adapter_type, types, names, closure_binding, argv_binding);
  List context_call = %(
    expr (* const void)
      (call (expr $context_type (ident $context_helper))
            (args (expr ("Func") (ident $closure_binding))))
  );
  List context_setup = %(
    declare (const $environment_name)
      (bindings
        (op = (bind $environment_local (*))
              (expr $environment_pointer_type
                (cast $environment_pointer_type $context_call))))
  );
  List rewritten = _rewrite_lambda_captures(
    compiler, body, slots, environment_local, environment_pointer_type);
  rewritten = _node(compiler, rewritten);
  _publish_func_adapter(
    compiler, lambda_binding, closure_binding, argv_binding, rewritten,
    %(@locals $context_setup));

  List signature = _signature(compiler, entries);
  if (compiler.inline_header) {
    List bridge = _func_bridge_binding(compiler, "func_from_capture");
    Array parameters = [], factory_values = [];
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
    List factory_construction = _func_context_call(
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
  List construction = _func_context_call(
    environment_value_type, context_value, lambda_binding,
    adapter_type, signature, constructor, constructor_type);
  return %(
    expr ("Func")
      (parens
        (block @{capture_locals.list_free()} $context_storage
               (stmnt $construction)))
  );
}

/** The parameter types of a lambda's function signature, keeping typed
    declarators; a bare parameter is a `Var`. */
List Compiler.lambda_param_types(Compiler compiler, List entries) {
  if (!entries) return %((void));
  Array types = [];
  foreach (List entry, entries)
    match (entry) {
      case %(binding ? ?): types.push(%("Var"));
      case %(param ? ?): {
        Type type = entry.type_from_ast().declared();
        if (type.car() == <&> || type.car() == <opt-ref>)
          type = cons(
            type.car(), compiler.sym.normalize_declared_type(type.cdr()));
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
    /* Only a meta body leaves a noncapturing `Func` lambda unlifted. */
    case %(expr ("Func") (lambda (params *entries) ?body)): {
      Type signature = %(
        (func ${compiler.lambda_param_types(entries)}) "Var");
      return compiler.lift_func_expression(
        %(expr $signature (lambda (params @entries) $body)));
    }
    case %(expr ?type (lambda (params *entries) ?body)): {
      String lname = compiler.fresh_name("lambda");
      List lambda_binding = compiler.sym.introduce(lname);
      List decl_params = _params_to_decl_params(entries);
      compiler.add_early(compiler.wrapper_function(
        %(static "Var"), lambda_binding, decl_params.cdr(),
        _helper_body(compiler, body, NULL).cdr()));
      return %(expr $type (ident $lambda_binding));
    }
  }
  return expression;
}

/* The runtime types a region's record and frame have. */
static String _frame_type = "ExceptionFrame";
static String _record_type = "X2CCleanup";
static String _handler_type = "ErrorHandler";

/* The walk state for one function body. */
typedef struct Walk {
  Compiler compiler;
  Array regions;
  int break_stop, continue_stop, origin;
  Map labels;
  Type return_type;
} *Walk;

static List _address_of(String spelling, List binding) {
  Type type = %(($spelling));
  return %(expr ${type.reference()} (op & (expr $type (ident $binding))));
}

/* One native call on a region's record or frame, as a statement. */
static List _region_call(String function, String type, List binding) =>
  %(stmnt (expr (void)
    (call $function (args ${_address_of(type, binding)}))));

/* Introduce a name this pass owns. The emitted declaration spells this
   binding, so the record a region pushes and the record its exits leave are
   one name by construction. */
static List _region_binding(Compiler compiler, String role) =>
  compiler.sym.introduce(compiler.fresh_name(role));

/* The statements that leave a `defer` region: the runtime unlinks the
   record and calls its thunk. */
static List _defer_cleanup(List record) =>
  %(${_region_call("x2c_cleanup_leave", _record_type, record)});

/* The first label a finalizer defines, or NULL. The statements that leave a
   region run on every path that leaves it, so a label among them would be
   defined once per path. */
static Var _finalizer_label(Var value, int origin, int &at) {
  Array pending = $auto([value]), origins = $auto([origin]);
  while (pending.len()) {
    Var current = pending.take_last();
    int here = origins.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node) {
      case %(function *): continue;
      case %(expr *): continue;
      case %(at ?(int inner) ?wrapped): {
        pending.push(wrapped);
        origins.push(inner);
        continue;
      }
      case %(label ?name *): {
        at = here;
        return name;
      }
    }
    foreach (Var child, node) {
      pending.push(child);
      origins.push(here);
    }
  }
  return NULL;
}

/* The statements that leave a `try` region, in the order the frame
   requires: a catch clause closes and clears its handler, a finalizer runs
   under the frame's run-once claim, and the frame leaves last. Claiming also
   retires the landing, so a `raise` from the finalizer reaches the enclosing
   frame instead of re-entering this one and looping. They are lowered. */
static List _try_cleanup(
  List frame, List handle, List finalizer, int has_clause) {
  Array body = [];
  if (has_clause) {
    Type handler = %(($_handler_type));
    body.push(
      %(stmnt (expr (void)
        (call "x2c_error_catch_close"
          (args (expr $handler (ident $handle)))))));
    body.push(
      %(stmnt (expr $handler
        (op = (expr $handler (ident $handle)) (expr $handler (nil))))));
  }
  if (finalizer) body.push(finalizer);
  List statements = body.list_free();
  if (finalizer)
    statements = %((if (expr (int)
      (call "x2c_exception_claim" (args ${_address_of(_frame_type, frame)})))
      (block @statements)));
  statements = statements.append(
    %(${_region_call("x2c_exception_leave", _frame_type, frame)}));
  return %(code-value "lowered" (seq @statements) ());
}

/* The statements a lowered sequence holds, or `code` itself. */
static List _statements(List code) {
  match (code) case %(code-value ? (seq *statements) ?): return statements;
  return code;
}

/* The statements that leave every region down to `stop`, innermost first.
   Each region runs its own statements before the next one out, so an inner
   frame leaves before an outer defer runs. */
static List _unwind(Walk walk, int stop) {
  Array statements = [];
  for (int i = (int) walk.regions.len() - 1; i >= stop; i--)
    foreach (List statement, walk.regions[i].list().car().list())
      statements.push(statement);
  return statements.list_free();
}

/* Wrap a transfer in the cleanup it runs first. A transfer that leaves no
   region keeps its own shape. */
static List _transfer(Walk walk, int stop, List statement) {
  List cleanup = _unwind(walk, stop);
  return cleanup ? %(block @cleanup $statement) : statement;
}

/* The open regions, innermost first. A label's ancestry is this list, and a
   jump may only leave a suffix of it. */
static List _region_path(Walk walk) {
  List path = %();
  foreach (List region, walk.regions) path = cons(region.cadr(), path);
  return path;
}

/* A label reads as a binding, as a wrapped expression, or as the bare name
   a macro wrote. */
static String _label_spelling(Var label) {
  if (label is <string>) return label;
  if (label is not <list>) return NULL;
  List node = label;
  match (node) {
    case %(ident ?binding): return binding_identity_spelling(binding);
    case %(!or (expr ? ?inner) (parens ?inner)): return _label_spelling(inner);
    case %(?(String name)): return name;
  }
  return binding_identity_spelling(node);
}

/* Collect each label's region ancestry before any `goto` is rewritten, so a
   jump backward to a label reads the same ancestry as a jump forward. The
   ancestry is the chain of region nodes enclosing the label, and the rewrite
   compares against the same nodes. */
static void _collect_labels(Walk walk, Var value, List path) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    // A label is a statement, and an expression nests as deeply as it is
    // long, so the walk stops here.
    case %(expr *): return;
    case %(label ?name *rest): {
      String spelling = _label_spelling(name);
      if (spelling) walk.labels[spelling] = path;
      foreach (Var child, rest) _collect_labels(walk, child, path);
      return;
    }
    /* Each region a construct opens has its own identity: a `try` protects
       its body and each catch arm separately, while its guards and its
       finalizer run outside the region and keep the enclosing path. */
    case %(try ?body ?clause ?finalizer *): {
      _collect_labels(walk, body, cons(body, path));
      match (clause)
        case %(catchcases ?records ?handle):
          foreach (List record, records) {
            _collect_labels(walk, record.car(), path);
            List arm = record.cadr();
            _collect_labels(walk, arm, cons(arm, path));
          }
      _collect_labels(walk, finalizer, path);
      return;
    }
    case %(defer ?body *): {
      _collect_labels(walk, body, cons(body, path));
      return;
    }
    case %(localinit ?guard ?body): {
      _collect_labels(walk, guard, path);
      _collect_labels(walk, body, cons(node, path));
      return;
    }
  }
  foreach (Var child, node) _collect_labels(walk, child, path);
}

/* Report at `origin`, and leave the compiler's origin as it was for whatever
   reports next. */
static void _report_at(Walk w, int origin, String message, List note) {
  $let(w.compiler.origin, origin)
    w.compiler.report_error(<emit>, message, NULL, note);
}

/* Reject a jump that would enter a region it did not open, and return the
   depth the jump unwinds to. */
static int _goto_stop(Walk walk, Var label) {
  String name = _label_spelling(label);
  Var stored;
  if (!name || !walk.labels.try_get(name, stored)) {
    _report_at(
      walk, walk.origin, "goto target label is not defined in this function",
      NULL);
    return (int) walk.regions.len();
  }
  List target = stored, source = _region_path(walk);
  int source_depth = source.len(), target_depth = target.len();
  List suffix = source;
  for (int i = source_depth; i > target_depth && suffix; i--)
    suffix = suffix.cdr();
  if (target_depth > source_depth || suffix !== target) {
    _report_at(
      walk, walk.origin,
      "goto cannot enter or cross a protected cleanup region",
      %("jump only within the same region or outward"));
    return (int) walk.regions.len();
  }
  return target_depth;
}

/* C requires automatic state changed after `sigsetjmp` to be volatile once
   `siglongjmp` returns. These are the forms that change their left operand;
   the operand names the object directly, or names a pointer that holds it. */
static Var _changed_operand(Compiler c, List node) {
  match (node) {
    case %(op ?operator ?target *): {
      if (operator is <symbol> && ast_changes_left_operand(operator))
        return target;
      return NULL;
    }
    case %(postfix ? ?target): return target;
    case %(call ?(String helper)
                (args (expr ? (op & (parens ?target))) *)): {
      if (helper == "x2c_var_update_volatile"
          || helper == "x2c_var_postfix_volatile"
          || helper == "Var_update" || helper == "Var_postfix") return target;
      Type native = c.sym.resolve_numeric_type(target.list().cadr());
      if (native && helper == native.var_numeric_update_helper())
        return target;
      foreach (Var (key, value), c.protocol_helpers)
        match (key)
          case %("protocol-update-helper" *):
            if (value == helper) return target;
    }
  }
  return NULL;
}

static int _automatic_static_input(Compiler c, List binding) {
  Var automatic, stored;
  Map facts = c.semantic_binding_facts();
  if (!facts.try_get(%(automatic $binding), automatic) ||
      !automatic.truth()) return 0;
  if (!facts.try_get(%(type $binding), stored)) return 1;
  Type type = stored;
  return !type.is_static() && !type.is_extern() && !type.is_threaded();
}

/* The operand of sizeof is unevaluated except for VLA dimensions. Inspect
   those dimensions through the same static-input classifier as an ordinary
   initializer, without evaluating calls in a fixed-size operand. */
static int _runtime_sizeof_dimensions(Compiler c, List operand, Map runtime) {
  Array pending = $auto([operand]);
  while (pending.len()) {
    List node = pending.take_last();
    match (node)
      case %(dim ?dimension): {
        if (dimension && c.static_value_is_runtime(dimension, runtime))
          return 1;
        continue;
      }
    foreach (Var child, node)
      if (child is <list>) pending.push(child);
  }
  return 0;
}

/** Reports whether the static initializer `value` has to run at runtime,
    because it calls, allocates, or reads an object other than a function
    name. `runtime` holds the function-local statics already known to run
    that way, or is `NULL` at file scope.
*/
int Compiler.static_value_is_runtime(Compiler c, List value, Map runtime) {
  Array pending = $auto([]), modes = $auto([]);
  pending.push(value);
  modes.push(0);
  while (pending.len()) {
    List node = pending.take_last();
    int address = modes.take_last();
    if (address) {
      match (node) {
        case %(!or (expr ? ?inner) (parens ?inner)
                   (op . ?inner ?)): {
          pending.push(inner);
          modes.push(1);
          continue;
        }
        case %(ident ?binding): {
          if ((runtime && binding in runtime) ||
              _automatic_static_input(c, binding)) return 1;
          continue;
        }
        case %(index (!set ?base (expr ?type ?)) ?index): {
          pending.push(index);
          modes.push(0);
          pending.push(base);
          modes.push(type.list().type().is_array());
          continue;
        }
        case %(op (!quote *) ?inner): {
          pending.push(inner);
          modes.push(0);
          continue;
        }
      }
      return 1;
    }
    match (node) {
      case %((!or cache call var array map varray vmap initval cons append) *):
        return 1;
      case %(expr ?type (ident ?binding)): {
        if ((runtime && binding in runtime) ||
            _automatic_static_input(c, binding)) return 1;
        if (%(function $binding) in c.semantic_binding_facts()) continue;
        Type native = type;
        if (native && !native.is_enum() && !native.is_function() &&
            !native.is_array() &&
            (native.is_pointer() || !native.contains(<const>))) return 1;
        continue;
      }
      case %(expr ? (op & ?inner)): {
        pending.push(inner);
        modes.push(1);
        continue;
      }
      case %(expr ?type (!set ?content (index *))): {
        Type native = type;
        if (native.is_array()) {
          pending.push(content);
          modes.push(1);
          continue;
        }
        if (native.is_pointer() || !native.contains(<const>)) return 1;
      }
      case %(expr ? (sizeof ?operand)): {
        if (_runtime_sizeof_dimensions(c, operand, runtime)) return 1;
        continue;
      }
    }
    foreach (Var child, node)
      if (child is <list>) {
        pending.push(child);
        modes.push(0);
      }
  }
  return 0;
}

static int _runtime_static_declaration(
  Compiler c, List node, Map runtime) {
  int found = 0;
  match (node) {
    case %(at ? ?body): return _runtime_static_declaration(c, body, runtime);
    case %(declare (!set ?type (*)) (bindings *bindings)):
      if (type.list().type().is_static())
        foreach (List binding, bindings)
          match (binding)
            case %(op = (bind ?name ?) ?value):
              if (c.static_value_is_runtime(value, runtime)) {
                runtime[name] = 1;
                found = 1;
              }
  }
  return found;
}

/* A static local whose initializer runs at runtime protects the remainder
   of its block just as a cleanup region does: a jump may not enter past the
   initializer. Keeping the canonical binding makes shadowing and generated
   syntax use the same object reference. */
static List _static_regions(Compiler c, List ast, Map runtime) {
  match (ast) {
    case %((!or function localinit expr declare typedef) *): return ast;
    case %(block *statements): {
      Array before = [];
      foreach (List statement, statements) {
        if (_runtime_static_declaration(c, statement, runtime)) {
          List rest = statements;
          for (int i = 0; i <= before.len(); i++) rest = rest.cdr();
          List body = _static_regions(c, %(block @rest), runtime);
          before.push(%(localinit $statement $body));
          return %(block @{before.list_free()});
        }
        before.push(_static_regions(c, statement, runtime));
      }
      return %(block @{before.list_free()});
    }
  }
  Var child;
  $ast.rewrite_children(ast, child, _static_regions(c, child, runtime));
}

/* Names whose storage a transfer may leave stale: those a `try` body writes,
   and those a `defer` inside one writes through its environment. The flag
   covers a subtree, so a write outside every `try` preserves nothing.
   `holders` gains the pointers the body writes through, whose own locals
   `_collect_aliased` resolves.

   A local that only a callee writes, through an address the body hands it,
   is not qualified. Taking its address already forces it to memory, so the
   register `siglongjmp` would restore is not where its value lives, and
   qualifying it would discard the qualifier at every such call instead. */
static void _collect_preserved(
  Compiler c, Var value, int in_try, Map names, Map holders) {
  /* A long expression chain nests as deeply as it is long, so the walk keeps
     its pending work off the C stack. */
  Array pending = $auto([value]), flags = $auto([in_try]);
  while (pending.len()) {
    Var current = pending.take_last();
    int inside = flags.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    if (inside) {
      Var operand = _changed_operand(c, node);
      String name = ast_direct_identifier(operand);
      if (name) names[name] = 1;
      String holder = ast_indirect_identifier(operand);
      if (holder) holders[holder] = 1;
    }
    match (node) {
      case %(function *): continue;
      case %(defer ?body ? ? ? ?written *): {
        if (inside)
          foreach (List binding, written) {
            String captured = binding_identity_spelling(binding);
            if (captured) names[captured] = 1;
          }
        pending.push(body);
        flags.push(inside);
        continue;
      }
      case %(try ?body ?clause ?finalizer *): {
        foreach (Var part, %($body $clause $finalizer)) {
          pending.push(part);
          flags.push(1);
        }
        continue;
      }
    }
    foreach (Var child, node) {
      pending.push(child);
      flags.push(inside);
    }
  }
}

/* Preserve the locals whose address one of `holders` took. A write through
   such a pointer changes the local without naming it, so the local needs the
   qualifier the write itself does not ask for. `pointers` gains the holders
   that resolved, because their pointee type has to carry the qualifier too. */
static void _collect_aliased(
  Var value, Map holders, Map names, Map pointers) {
  Array pending = $auto([value]);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node) case %(op = ?target ?source): {
      String addressed = ast_addressed_identifier(source), holder = NULL;
      match (target) case %(bind ?binding ?):
        holder = binding_identity_spelling(binding);
      if (!holder) holder = ast_direct_identifier(target);
      if (addressed && holder && holder in holders) {
        names[addressed] = 1;
        pointers[holder] = 1;
      }
    }
    foreach (Var child, node) pending.push(child);
  }
}

/* Rewrite a construct's body with the transfer barriers it establishes. A
   loop bounds both `break` and `continue`; a switch bounds only `break`,
   because a `continue` inside it still targets the enclosing loop. */
static Var _bounded(Walk walk, Var body, int is_loop) {
  int saved_break = walk.break_stop, saved_continue = walk.continue_stop;
  walk.break_stop = (int) walk.regions.len();
  if (is_loop) walk.continue_stop = (int) walk.regions.len();
  Var result = _rewrite(walk, body);
  walk.break_stop = saved_break;
  walk.continue_stop = saved_continue;
  return result;
}

/* Rewrite a region's body and its handlers with the region open. */
static Var _inside(Walk walk, List cleanup, List marker, Var body) {
  walk.regions.push(%(${_statements(cleanup)} $marker));
  Var result = _rewrite(walk, body);
  walk.regions.take_last();
  return result;
}

/* Qualify one binding that a transfer may leave stale. */
static List _preserve_binding(List bind, Map names) {
  match (bind)
    case %(bind ?name ?mods): {
      String spelling = binding_identity_spelling(name);
      if (spelling && spelling in names && !mods.contains(<volatile>))
        return %(bind $name ${cons(<volatile>, mods)});
    }
  return bind;
}

static int _declares_preserved(List bindings, Map names) {
  foreach (List binding, bindings.cdr())
    match (binding)
      case %(!or (bind ?name ?) (op = (bind ?name ?) ?)): {
        String spelling = binding_identity_spelling(name);
        if (spelling && spelling in names) return 1;
      }
  return 0;
}

/* Static, extern, threaded, and typedef declarations do not have automatic
   storage, so a transfer cannot leave them stale. */
static int _is_automatic(List declaration) {
  Type type = declaration.cadr();
  return !type.is_static() && !type.is_extern() && !type.is_typedef() &&
         !type.is_threaded();
}

/* A pointer that holds the address of a preserved local points at a volatile
   object, so its pointee type must say so or C rejects dropping the
   qualifier. `pointers` names the holders the walk resolved, which covers a
   pointer assigned after its declaration; an initializer that takes the
   address directly says the same thing on its own. */
static int _declares_pointee(List bindings, Map names, Map pointers) {
  foreach (List binding, bindings.cdr()) {
    List declarator = binding;
    match (binding) case %(op = ?bind ?value): {
      String addressed = ast_addressed_identifier(value);
      if (addressed && addressed in names) return 1;
      declarator = bind;
    }
    match (declarator) case %(bind ?name ?): {
      String spelling = binding_identity_spelling(name);
      if (spelling && spelling in pointers) return 1;
    }
  }
  return 0;
}

/* Qualify the declarations and parameters the sets name. C puts a qualifier
   on the whole declaration - on the declarator for the object itself, and on
   the base type for a pointee - so a statement that qualifies any of several
   names splits into one declaration each. */
static Var _preserve(Var value, Map names, Map pointers) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  // Only declarations and parameters carry a qualifier, and neither appears
  // inside an expression.
  match (node) case %(expr *): return value;
  match (node) {
    case %(param ?type ?bind):
      return %(param $type ${_preserve_binding(bind, names)});
    case %(block *statements): {
      Array output = [];
      foreach (Var statement, statements) {
        List origin = NULL, Var inner = statement;
        match (inner) case %(at ?anchor ?wrapped): {
          origin = anchor;
          inner = wrapped;
        }
        /* Split before qualifying, so a base-type qualifier one declarator
           needs does not reach the names beside it. */
        match (inner)
          case %(!set ?declaration
                 ((!or declare decl) ?type
                  (!set ?bindings (bindings ? ? *)))):
            if (_is_automatic(declaration) &&
                (_declares_preserved(bindings, names) ||
                 _declares_pointee(bindings, names, pointers))) {
              Symbol head = declaration.car();
              foreach (List binding, bindings.cdr()) {
                Var one = _preserve(
                  %($head $type (bindings $binding)), names, pointers);
                output.push(origin ? %(at $origin $one) : one);
              }
              continue;
            }
        output.push(_preserve(statement, names, pointers));
      }
      return %(block @{output.list_free()});
    }
    case %(!set ?declaration
           ((!or declare decl) ?type (!set ?bindings (bindings *)))): {
      Symbol head = declaration.car();
      if (!_is_automatic(declaration)) return node;
      if (_declares_pointee(bindings, names, pointers) &&
          !type.type().flatten_all().contains(<volatile>))
        type = cons(<volatile>, type);
      Array preserved = [];
      foreach (List binding, bindings.cdr())
        match (binding) {
          case %(op = ?bind ?value):
            preserved.push(
              %(op = ${_preserve_binding(bind, names)} $value));
          case %(bind * ): preserved.push(_preserve_binding(binding, names));
        }
      return %($head $type (bindings @{preserved.list_free()}));
    }
  }
  Var child;
  $ast.rewrite_children(node, child, _preserve(child, names, pointers));
}

/* Save the returned value before cleanup runs, since cleanup may change the
   state the expression read. */
static List _return_value(Walk walk, List expression) {
  List binding = _region_binding(walk.compiler, "return_value");
  Type type = walk.return_type;
  /* The declarator carries the type's pointer and array modifiers, so the
     saved value declares the way the function's result is spelled. */
  List (base, mods) = type.declaration_parts();
  List declaration = %(declare $base
    (bindings (op = (bind $binding $mods) $expression)));
  List statement = _transfer(walk, 0, %(return (expr $type (ident $binding))));
  return %(block $declaration $statement);
}

static List _defer_block(Walk walk, List body, List environment,
                         List callback, List records, List record,
                         List cleanup) {
  Array statements = [];
  List argument = %(expr (* void) (nil));
  if (environment) {
    Type type = %(${binding_identity_spelling(environment)});
    List local = _region_binding(walk.compiler, "defer_env");
    Array values = [];
    foreach (List capture, records) {
      List source = capture.car(), field = capture.caddr();
      Type stored = capture.cadr();
      List address = %(expr ${stored.reference()}
        (op & (expr $stored (ident $source))));
      String name = binding_identity_spelling(field);
      values.push(%(dotinit ($name)
        (expr (* const void) (cast (* const void) $address))));
    }
    List value = %(expr $type (composite
      (commas @{values.list_free()})));
    statements.push(_value_declaration(type, local, value));
    argument = %(expr ${type.reference()}
      (op & (expr $type (ident $local))));
  }
  List value = %(expr ($_record_type) (composite (commas
    (dotinit ("fn") (expr () (ident $callback)))
    (dotinit ("env") $argument))));
  statements.push(_value_declaration(%($_record_type), record, value));
  statements.push(_region_call("x2c_cleanup_push", _record_type, record));
  statements.push(body);
  foreach (List statement, cleanup) statements.push(statement);
  return %(block @{statements.list_free()});
}

static List _catch_call(Type type, String name, List arguments) =>
  %(expr $type (call $name (args @arguments)));

static List _catch_statement(String name, List arguments) =>
  %(stmnt ${_catch_call(%(void), name, arguments)});

static List _catch_value(Type type, List binding) =>
  %(expr $type (ident $binding));

static List _catch_arms(Compiler c, List bodies, List frame, List handle) {
  List selected = _region_binding(c, "catch_selected");
  List choice = NULL;
  int index = bodies.len();
  foreach (List body, bodies.reverse()) {
    index--;
    choice = choice
      ? %(if (expr (int) (op == ${_catch_value(%(int), selected)}
                               ${_integer_expression(index)})) $body $choice)
      : body;
  }
  List declaration = bodies.len() > 1
    ? %(${_value_declaration(%(int), selected,
      _catch_call(%(int), "x2c_error_catch_selected",
                  %(${_catch_value(%("ErrorHandler"), handle)})))})
    : NULL;
  return %(block @declaration
    ${_catch_statement("x2c_error_catch_detach",
      %(${_catch_value(%("ErrorHandler"), handle)}))}
    ${_region_call("x2c_exception_mark_handled", _frame_type, frame)}
    $choice);
}

/* The catch clause's site, patterns, and handler. */
static List _try_declarations(Compiler c, List clause, List frame,
                              List handle) {
  List address = _address_of(_frame_type, frame);
  Array declarations = [];
  if (clause) {
    List records = clause.cadr();
    int count = records.len(), fallback = -1, index = 0;
    String state = "ERROR_CATCH_PENDING";
    List arms = _region_binding(c, "catch_arms");
    List site = _region_binding(c, "catch_site");
    List patterns = _region_binding(c, "catch_patterns");
    Type arms_type = %((dim ${_integer_expression(count)}) "MatchCaptureSite");
    Type patterns_type = %((dim ${_integer_expression(count)}) "Var");
    declarations.push(_value_declaration(
      %((dim ${_integer_expression(count)}) static "MatchCaptureSite"), arms, NULL));
    declarations.push(_value_declaration(patterns_type, patterns, NULL));
    Array preparation = [];
    foreach (List record, records) {
      List pattern = record.car();
      if (pattern) {
        if (!c.match_pattern_is_static(pattern))
          state = "ERROR_CATCH_TRANSIENT";
        List value = _catch_call(%("Var"), "List_var", %($pattern));
        preparation.push(%(stmnt (expr ("Var")
          (op = (expr ("Var") (index
            ${_catch_value(patterns_type, patterns)}
            ${_integer_expression(index)})) $value))));
      }
      else fallback = index;
      index++;
    }
    Type site_type = %("ErrorCatchSite");
    List initializer = %(expr $site_type (composite (commas
      ${_catch_value(arms_type, arms)} ${_integer_expression(fallback)}
      ${_integer_expression(count)} (expr (int) $state) ${_integer_expression(-1)})));
    declarations.push(_value_declaration(
      %(static "ErrorCatchSite"), site, initializer));
    List site_address = _address_of("ErrorCatchSite", site);
    declarations.push(%(if ${_catch_call(%(int),
      "x2c_error_catch_site_pending", %($site_address))}
      (block @{preparation.list_free()})));
    declarations.push(_value_declaration(%(volatile "ErrorHandler"), handle,
      _catch_call(%("ErrorHandler"), "x2c_error_catch_site_push",
        %($address $site_address ${_catch_value(patterns_type, patterns)}))));
  }
  return %(code-value "lowered" (seq @{declarations.list_free()}) ());
}

/* What runs when the frame lands: the selected catch arm, or the cleanup
   and an unreachable end. */
static List _try_landing(Compiler c, List clause, List frame, List handle,
                         List cleanup, List bodies) {
  List unhandled = %(block @{_statements(cleanup)}
    ${_catch_statement("__builtin_unreachable", NULL)});
  List landing = clause
    ? %(if ${_catch_call(%(int), "x2c_exception_is_error_target",
             %(${_address_of(_frame_type, frame)}))}
        ${_catch_arms(c, bodies, frame, handle)} $unhandled)
    : unhandled;
  return %(code-value "lowered" $landing ());
}

/* A try region's frame: a fresh binding, returned as a bound reference
   with the binding in `binding`. */
static List _try_frame(Compiler c, List &binding) {
  binding = _region_binding(c, "exception_frame");
  return %(code-value "bound"
    ${_catch_value(%("ExceptionFrame"), binding)} ());
}

/* A try region's body, lowered inside the region `cleanup` leaves. */
static List _try_region(Walk walk, List cleanup, List body) =>
  %(code-value "lowered" ${_inside(walk, cleanup, body, body)} ());

/* The try producers `src/builtins.x` compiles into the compiler. The
   template calls them by name in the unit it is applied to. */
List builtin_try_frame_declaration(Var frame);
List builtin_try_cleanup_placement(Var cleanup);

/* A try region pushes its frame and lands on it when something raises. */
macro open Statement $compiler_try_shape(Expr $frame, Statement $declarations,
    Statement $body, Statement $landing, Statement $cleanup) {
  {
    $builtin_try_frame_declaration($frame)...
    $declarations
    x2c_exception_push(&$frame);
    if (!sigsetjmp($frame.env, 0)) $body
    else { x2c_exception_landed(&$frame); $landing }
    $builtin_try_cleanup_placement($cleanup)...
  }
}

static Var _rewrite(Walk walk, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  // An expression holds no transfer and no region, and nests as deeply as it
  // is long, so the walk stops here.
  match (node) case %(expr *): return value;
  match (node) {
    case %(defer ?body ?env ?callback ?records ?): {
      walk.compiler.needs_exception = 1;
      List record = _region_binding(walk.compiler, "defer_record");
      List cleanup = _defer_cleanup(record);
      return _defer_block(walk, _inside(walk, cleanup, body, body),
                          env, callback, records, record, cleanup);
    }
    case %(try ?body ?clause ?finalizer): {
      Compiler c = walk.compiler;
      List binding = NULL;
      List frame = _try_frame(c, binding);
      List handle = clause ? clause.caddr().list() : NULL;
      int labelled_at = walk.origin;
      Var labelled = _finalizer_label(finalizer, walk.origin, labelled_at);
      if (labelled) {
        String name = _label_spelling(labelled);
        _report_at(
          walk, labelled_at, "a finally body cannot define a label",
          %("a finalizer runs on every path that leaves its region, so '${
            name ? name : "this label"}' would be defined once for each"));
      }
      List cleanup = _try_cleanup(
        binding, handle, _rewrite(walk, finalizer), !!clause);
      List body_out = _try_region(walk, cleanup, body);
      /* A catch arm runs inside the region it handles, so it leaves the
         same statements behind on its own exits. Each arm is its own
         region, which a jump from the body may not enter. */
      Array bodies = [];
      if (clause) foreach (List record, clause.cadr().list()) {
        List arm = record.cadr();
        bodies.push(_inside(walk, cleanup, arm, arm));
      }
      List declarations = _try_declarations(c, clause, binding, handle);
      List landing = _try_landing(
        c, clause, binding, handle, cleanup, bodies.list_free());
      Macro shape = $compiler_try_shape;
      return c.bind_syntax(
        shape(frame, declarations, body_out, landing, cleanup),
        AST_BLOCK, c.return_type);
    }
    /* A function-static initializer leaves its own record at the end of its
       block. No exit runs that record, but a jump still may not enter the
       region, so it takes part in the ancestry a label is compared by. */
    case %(localinit ?guard ?body):
      return %(localinit ${_rewrite(walk, guard)}
               ${_inside(walk, NULL, node, body)});
    case %(at ?(int origin) ?inner): {
      int previous = walk.origin;
      walk.origin = origin;
      Var lowered = _rewrite(walk, inner);
      walk.origin = previous;
      return %(at $origin $lowered);
    }
    case %(return): return _transfer(walk, 0, node);
    case %(return (!set ?expression (expr ? ?))): {
      /* Only a region that runs something can change what the expression
         read, so a static-local region alone leaves the return as it is. */
      if (!_unwind(walk, 0)) return node;
      return _return_value(walk, expression);
    }
    case %(break): return _transfer(walk, walk.break_stop, node);
    case %(continue): return _transfer(walk, walk.continue_stop, node);
    case %(goto ?label): return _transfer(walk, _goto_stop(walk, label), node);
    case %(while ?condition ?body):
      return %(while ${_rewrite(walk, condition)} ${_bounded(walk, body, 1)});
    case %(do ?body ?condition):
      return %(do ${_bounded(walk, body, 1)} ${_rewrite(walk, condition)});
    case %(for ?initial ?condition ?increment ?body):
      return %(for ${_rewrite(walk, initial)} ${_rewrite(walk, condition)}
               ${_rewrite(walk, increment)} ${_bounded(walk, body, 1)});
    case %(switch ?expression ?body):
      return %(switch ${_rewrite(walk, expression)}
               ${_bounded(walk, body, 0)});
    /* A `match` emits a switch over its arms, so an arm's `break` leaves the
       match and no region with it. Its `continue` still reaches the
       enclosing loop. */
    case %(matchcases ?subject ?records):
      return %(matchcases ${_rewrite(walk, subject)}
               ${_bounded(walk, records, 0)});
    case %(function *): return _function(walk.compiler, node);
  }
  Var child;
  $ast.rewrite_children(node, child, _rewrite(walk, child));
}

/* Each function walks on its own: no loop, switch, or region spans a
   function boundary, including a lambda body lifted into a sibling. */
static List _function(Compiler compiler, List node) {
  match (node)
    case %(function ?type ?bindings ?body): {
      List declaration = %(declare $type (bindings $bindings));
      struct Walk state = {
        compiler, [], 0, 0, 0, {},
        cdr(declaration.type_from_ast()).type().declared()
      };
      Walk walk = &state;
      Map runtime = {};
      body = _static_regions(compiler, body, runtime);
      _collect_labels(walk, body, NULL);
      Map preserved = {}, holders = {}, pointers = {};
      _collect_preserved(compiler, body, 0, preserved, holders);
      if (holders.len())
        _collect_aliased(body, holders, preserved, pointers);
      List rewritten = _rewrite(walk, body);
      if (preserved.len()) {
        rewritten = _preserve(rewritten, preserved, pointers);
        bindings = _preserve(bindings, preserved, pointers);
      }
      state.regions.free();
      return %(function $type $bindings $rewritten);
    }
  return node;
}

/* Unit normalization calls this at function completion. Expressions cannot
   contain an unlifted function, so no second unit-tree traversal is needed. */
static List _cleanup_unit(Compiler compiler, List node) {
  match (node) {
    case %(function *): return _function(compiler, node);
    case %(at ?origin ?inner):
      return %(at $origin ${_cleanup_unit(compiler, inner)});
  }
  return node;
}

// type coercion passes

static List _to_var(Compiler compiler, List expr) =>
  compiler.convert_expression(expr, %("Var"));

static List _symbol_expression(Symbol value) =>
  %(expr ("Symbol") "${(unsigned long) value}");

static List _truthy_expression(Compiler compiler, List expr) {
  if (!expr) return expr;
  List resolved = compiler.resolve_protocol_member(expr.cadr(), "truth");
  if (!resolved) return expr;
  (List binding, Type signature) = resolved;
  return %(expr (int) (call (expr $signature (ident $binding)) (args $expr)));
}

// call and binding passes

typedef enum PrintfLength {
  _printf_default,
  _printf_hh,
  _printf_h,
  _printf_l,
  _printf_ll,
  _printf_j,
  _printf_z,
  _printf_t,
  _printf_L
} PrintfLength;

static int _iter_immediate_consumer(String name) =>
  name == "Iter_try_next" || name == "Iter_next" ||
         name == "Iter_list" || name == "Iter_array" ||
         name == "Iter_foldl" || name == "Iter_any" ||
         name == "Iter_all" || name == "Iter_find" ||
         name == "Iter_count" || name == "Iter_sum" ||
         name == "Iter_product" || name == "Iter_min" ||
         name == "Iter_max";

static int _printf_has_var(Compiler compiler, List args, int first_value) {
  int index = 0;
  foreach (List arg, args) {
    if (index++ < first_value) continue;
    if (compiler.sym.is_var_type(arg.cadr())) return 1;
  }
  return 0;
}

static void _printf_error(Compiler compiler, String family, String message) {
  String note = "printf-family call: %s".printf(family);
  compiler.report_error(<xform>, message, NULL, %($note));
}

static int _printf_is_digit(int ch) => ch >= '0' && ch <= '9';

static int _printf_valid_length(PrintfLength length, int conversion) {
  switch (conversion) {
    case 'd': case 'i': case 'o': case 'u': case 'x': case 'X':
      return length != _printf_L;
    case 'f': case 'F': case 'e': case 'E':
    case 'g': case 'G': case 'a': case 'A':
      return length == _printf_default || length == _printf_l ||
             length == _printf_L;
    case 'c': case 's':
      return length == _printf_default || length == _printf_l;
    case 'p': return length == _printf_default;
    case 'n': return length != _printf_L;
    default:  return 0;
  }
}

static Type _printf_integer_type(PrintfLength length, int is_unsigned) {
  switch (length) {
    case _printf_j: case _printf_z: case _printf_t: return NULL;
    case _printf_hh: case _printf_h: return %(int);
    case _printf_l:  return is_unsigned ? %(unsigned long) : %(long);
    case _printf_ll:
      return is_unsigned ? %(unsigned long long) : %(long long);
    default: return is_unsigned ? %(unsigned) : %(int);
  }
}

/* Native arguments retain C calling semantics. */
static void _lower_printf_value(
  Compiler compiler, Array values, int index, String family,
  PrintfLength length, int conversion) {
  List arg = values[index];
  if (!compiler.sym.is_var_type(arg.cadr())) return;

  Type target = NULL;
  if (conversion == 'd' || conversion == 'i')
    target = _printf_integer_type(length, 0);
  else if (conversion == 'o' || conversion == 'u' ||
           conversion == 'x' || conversion == 'X')
    target = _printf_integer_type(length, 1);
  else if (conversion == 'f' || conversion == 'F' ||
           conversion == 'e' || conversion == 'E' ||
           conversion == 'g' || conversion == 'G' ||
           conversion == 'a' || conversion == 'A')
    target = length == _printf_L ? %(long double) : %(double);
  else if (conversion == 'c' && length == _printf_default) target = %(int);
  else if (conversion == 's' && length == _printf_default) {
    values[index] = %(expr ("String") (call "Var_str" (args $arg)));
    return;
  }
  if (target) {
    values[index] = compiler.convert_expression(arg, target);
    return;
  }

  String message =
    "cannot infer a native argument for Var at %%%c"
      .printf(conversion);
  _printf_error(
    compiler, family,
    %"$message; use an explicit converter for this format conversion");
}

static void _lower_printf_star(
  Compiler compiler, Array values, int index, String family) {
  if (index >= values.len())
    _printf_error(compiler, family, "format consumes a missing '*' argument");
  List arg = values[index];
  if (compiler.sym.is_var_type(arg.cadr()))
    values[index] = compiler.convert_expression(arg, %(int));
}

// Align static format conversions with variadic arguments and lower only
// Var crossings. The parser understands the standard output grammar far
// enough to preserve native arguments around the safe automatic subset.
static List _lower_printf_vars(Compiler c, List ast) {
  (List callee, List args_node) = ast.cdr();
  const PrintfFn *info = callee.printf_family();
  if (!info) return ast;
  List args = args_node.cdr();
  if (!_printf_has_var(c, args, info.first_arg)) return ast;

  Array values = [];
  foreach (Var arg, args) values.push(arg);
  String family = (String) info.name;
  if (info.fmt_arg >= values.len())
    _printf_error(c, family, "call has no format argument");
  List format_arg = values[info.fmt_arg], int raw = 0;
  String format = c.printf_static_format(format_arg, raw);
  if (!format)
    _printf_error(
      c, family,
      "Var arguments require a single static format literal");

  int cursor = raw ? 1 : 0, end = raw ? format.len() - 1 : format.len();
  int value_index = info.first_arg;
  while (cursor < end) {
    if (raw && format[cursor] == '\\') {
      cursor += cursor + 1 < end ? 2 : 1;
      continue;
    }
    if (format[cursor++] != '%') continue;
    if (cursor >= end)
      _printf_error(c, family, "incomplete format conversion");
    if (format[cursor] == '%') {
      cursor++;
      continue;
    }

    int probe = cursor;
    while (probe < end && _printf_is_digit(format[probe])) probe++;
    if (probe < end && format[probe] == '$')
      _printf_error(
        c, family,
        "positional formats cannot infer Var argument types");

    while (cursor < end &&
           (format[cursor] == '-' || format[cursor] == '+' ||
            format[cursor] == ' ' || format[cursor] == '#' ||
            format[cursor] == '0'))
      cursor++;

    if (cursor < end && format[cursor] == '*') {
      cursor++;
      probe = cursor;
      while (probe < end && _printf_is_digit(format[probe])) probe++;
      if (probe < end && format[probe] == '$')
        _printf_error(
          c, family,
          "positional formats cannot infer Var argument types");
      _lower_printf_star(c, values, value_index++, family);
    }
    else while (cursor < end && _printf_is_digit(format[cursor])) cursor++;

    if (cursor < end && format[cursor] == '.') {
      cursor++;
      if (cursor < end && format[cursor] == '*') {
        cursor++;
        probe = cursor;
        while (probe < end && _printf_is_digit(format[probe])) probe++;
        if (probe < end && format[probe] == '$')
          _printf_error(
            c, family,
            "positional formats cannot infer Var argument types");
        _lower_printf_star(c, values, value_index++, family);
      }
      else while (cursor < end && _printf_is_digit(format[cursor])) cursor++;
    }

    PrintfLength length = _printf_default;
    if (cursor + 1 < end && format[cursor] == 'h' &&
        format[cursor + 1] == 'h') {
      length = _printf_hh;
      cursor += 2;
    }
    else if (cursor + 1 < end && format[cursor] == 'l' &&
             format[cursor + 1] == 'l') {
      length = _printf_ll;
      cursor += 2;
    }
    else if (cursor < end) {
      switch (format[cursor]) {
        case 'h': length = _printf_h; cursor++; break;
        case 'l': length = _printf_l; cursor++; break;
        case 'j': length = _printf_j; cursor++; break;
        case 'z': length = _printf_z; cursor++; break;
        case 't': length = _printf_t; cursor++; break;
        case 'L': length = _printf_L; cursor++; break;
      }
    }
    if (cursor >= end)
      _printf_error(c, family, "incomplete format conversion");
    int conversion = format[cursor++];
    if (!_printf_valid_length(length, conversion)) {
      String message =
        "unsupported or malformed format conversion %%%c"
          .printf(conversion);
      _printf_error(c, family, message);
    }
    if (value_index >= values.len()) {
      String message =
        "format conversion %%%c consumes a missing argument"
          .printf(conversion);
      _printf_error(c, family, message);
    }
    _lower_printf_value(
      c, values, value_index++, family, length, conversion);
  }

  for (int i = value_index; i < values.len(); i++) {
    List arg = values[i];
    if (c.sym.is_var_type(arg.cadr()))
      _printf_error(
        c, family,
        "Var argument has no corresponding format conversion");
  }
  List newargs = values.list_free();
  return %(call $callee (args @newargs));
}

static List _typed_call(
  Compiler compiler, List ast, List params, List args) {
  String callee_name = NULL;
  match (ast.cadr()) {
    case %(expr ? (ident ?binding)):
      callee_name = binding_identity_spelling(binding);
  }
  int list_varargs = callee_name == "List_list_n";
  if (compiler.fn_name && _iter_immediate_consumer(callee_name) && args)
    args = cons(compiler.complete_iter_chain(args.car()), args.cdr());
  Array values = [], int arg_index = 0;
  for (List p = params, a = args; a;
       p = p.cdr(), a = a.cdr(), arg_index++) {
    List param = (p ? p.car().list() : NULL), arg = a.car();
    List expected = param;
    if (list_varargs && arg_index > 0) expected = %("Var");
    if (param && param.car() == <param>) expected = param.type_from_ast();
    arg = compiler.maybe_adapt_func_arg(arg, expected);
    List converted = expected
      ? compiler.convert_expression(arg, expected)
      : compiler.lower_lambda_expr(arg);
    values.push(converted);
  }
  List newargs = values.list_free();
  return %(call ${ast.cadr()} (args @newargs));
}

static List _call(Compiler compiler, List ast) {
  ast = _lower_printf_vars(compiler, ast);
  match (ast) {
    case %(call (expr ((func ?matched_params) *) ?) (args *args)): {
      return _typed_call(
        compiler, ast, matched_params, args);
    }
    case %(call (expr ((!or (!quote *) & ^) (func ?pointer_params) *) ?)
                 (args *pointer_args)): {
      return _typed_call(
        compiler, ast, pointer_params, pointer_args);
    }
  }
  return ast;
}

// Inject conversions so assignment RHS matches the annotated LHS type.
static List _assignment(
  Compiler compiler, Symbol op, List lhs, List rhs) {
  if (lhs.match(%(expr ? (slice *))))
    compiler.report_error(
      <xform>, "slice expressions are not assignable",
      NULL, %("call the collection's setslice method explicitly"));
  match (lhs) {
    case %(expr ? (getindex (!set ?base (expr ?btype ?)) ?index)): {
      List base_type = btype;
      /* String is immutable and interned, so an in-place bracket write
         would mutate shared storage and leave its cached header hash
         stale. A raw write bypasses that invariant, while generic
         setindex returns a copy that this assignment would discard. */
      if (compiler.sym.is_string_type(base_type)) {
        String note = "String is immutable: use the copy-producing " +
                      "String.withindex, or bind a char * to write a " +
                      "transient String.malloc buffer";
        compiler.report_error(
          <xform>, "String does not support bracket assignment", NULL,
          %($note));
      }
      if (!compiler.resolve_protocol_member(base_type, "setindex"))
        compiler.report_error(
          <xform>, %"type $base_type does not support bracket assignment",
          NULL, %("use an explicit copy-producing method where available"));
      return %(setindex $base $index $rhs);
    }
  }
  rhs = compiler.convert_expression(rhs, lhs.cadr());
  return %(op $op $lhs $rhs);
}

static List _declaration(Compiler compiler, List ast) {
  match (ast) {
    case %((!set ?head (!or declare decl)) ?target
           (bindings *bound_list)): {
      Array values = [], List new_bind = NULL;
      foreach (Ast binding, bound_list) {
        new_bind = binding;
        match (binding)
          case %(op = (bind ?var ?mods) ?rhs): {
            Type target_type = %(declare $target
              (bindings (bind $var $mods))).type_from_ast();
            List native_target = %(expr $target_type (ident $var));
            List converted = compiler.convert_initializer(
              rhs, target_type, native_target);
            new_bind = %(
              op = (bind $var $mods) $converted
            );
            if (target_type.type().is_static())
              match (converted)
                case %(expr ("Func")
                       (ident (!set ?dependency (binding ? ?)))):
                  compiler.static_init_deps[var] = %($dependency);
          }
        values.push(new_bind);
      }
      List new_bindings = values.list_free();
      return %($head $target (bindings @new_bindings));
    }
  }
  return ast;
}

// A `Var` subscript of a native pointer or array reads as an integer.
static List _index(Compiler compiler, List ast) {
  match (ast)
    case %(index ?base (!set ?selector (expr ?type ?)))
      if (compiler.sym.is_var_type(type)): {
        List converted = compiler.convert_expression(selector, %(long));
        return %(index $base $converted);
      }
  return ast;
}

static List _destructure_source(
  Compiler compiler, List source, Type source_type) {
  // An integer, floating, or enumeration source cannot destructure. Reject
  // it before converting so the report names the construct the user wrote;
  // convert_expression would instead diagnose an integer reaching a
  // pointer.
  if (compiler.sym.resolve_numeric_type(source_type.canonicalize()))
    compiler.report_error(
      <type>, "destructuring requires a List source", NULL,
      %(("source type" $source_type)));
  List converted = compiler.convert_expression(source, %("List"));
  Type converted_type = NULL;
  match (converted)
    case %(expr ?type ?): converted_type = type;
  if (!compiler.sym.is_named_value_type(converted_type, "List"))
    compiler.report_error(
      <type>, "destructuring requires a List source", NULL,
      %(("source type" $source_type)));
  return converted;
}

// Build the List index expression used by each lowered target.
static List _element_at(List source, int index) {
  String text = %"$index";
  return %(expr ("Var") (getindex $source (literal (int) $text)));
}

static List _destructure_element(List temporary, int index) =>
  _element_at(%(expr ("List") (ident $temporary)), index);

// Expand predeclared assignment targets into left-to-right statements.
static List _destructure_assignments(List targets, List temporary) {
  int index = 0;
  return targets.map(
    %!(List target) using &index => {
      match (target)
        case %(expr ?type ?): {
          List value = _destructure_element(temporary, index++);
          return %(stmnt (expr $type (op = $target $value)));
        }
    });
}

// A discarded destructuring result retains the compact block lowering used
// before assignment destructuring became expression-valued.
static List _destructure_statement(Compiler compiler, List ast) {
  match (ast) {
    case %(stmnt (expr ?
             (dstrasgn (targets *targets)
                       (!set ?source (expr ?source_type ?))))): {
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));
      List temp_decl = %(declare ("List")
        (bindings (op = (bind $temporary ())
                      ${_destructure_source(
                        compiler, source, source_type)})));
      List assignments = _destructure_assignments(targets, temporary);
      return %(block $temp_decl @assignments);
    }
  }
  return ast;
}

// Lower declarations without a containing block so names retain outer scope.
static List _destructure_declaration(Compiler compiler, List ast) {
  match (ast) {
    case %(dstrdecl ?type (targets *targets)
                    (!set ?source (expr ?source_type ?))): {
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));

      Array declarations = [], expressions = [];
      foreach (List ident, targets) {
        declarations.push(%(bind $ident ()));
        expressions.push(%(expr $type (ident $ident)));
      }
      List target_decl =
        %(declare $type (bindings @{declarations.list_free()}));
      List temp_decl = %(declare ("List")
        (bindings (op = (bind $temporary ())
                      ${_destructure_source(
                        compiler, source, source_type)})));
      List assignments =
        _destructure_assignments(expressions.list_free(), temporary);
      return %(seq $target_decl $temp_decl @assignments);
    }
    case %(dstrdecl (params *parameters)
                    (!set ?source (expr ?source_type ?))): {
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));
      List temp_decl = %(declare ("List")
        (bindings (op = (bind $temporary ())
                      ${_destructure_source(
                        compiler, source, source_type)})));
      Array declarations = [];
      declarations.push(temp_decl);
      int index = 0;
      foreach (List parameter, parameters) match (parameter) {
        case %(param ?type ?bind): {
          List value = _destructure_element(temporary, index++);
          declarations.push(%( declare $type (bindings (op = $bind $value)) ));
        }
      }
      return %(seq @{declarations.list_free()});
    }
  }
  return ast;
}

/* Cell rewriting needs declaration sites, so lower destructuring
   with its existing transformation before analyzing a function body. */
static List _lower_lambda_destructuring(Compiler compiler, List ast) {
  if (!ast) return ast;
  match (ast) {
    case %(dstrdecl *):
      return _destructure_declaration(compiler, ast);
  }
  // The recursion below then only descends into subtrees it will rewrite.
  if (!ast_contains_head(ast, <dstrdecl>)) return ast;
  return Ast.rewrite_children(
    ast, %!(List child) => _lower_lambda_destructuring(compiler, child));
}

/* Keep the source's exact static type and value in one result temporary, then
   convert that temporary to List once for the left-to-right assignments. */
static List _value_declaration(Type type, List binding, List value) {
  (List base, List mods) = type.declaration_parts();
  return value
    ? %(declare $base (bindings (op = (bind $binding $mods) $value)))
    : %(declare $base (bindings (bind $binding $mods)));
}

static List _destructure_value(Compiler compiler, List ast) {
  match (ast) {
    case %(dstrasgn (targets *targets)
                    (!set ?source (expr ?type ?))): {
      List result = compiler.sym.introduce(
        compiler.fresh_name("destructure_result"));
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));
      List result_expr = %(expr $type (ident $result));
      List converted = _destructure_source(
        compiler, result_expr, type);
      List assignments = _destructure_assignments(targets, temporary);
      return %(parens (block
        ${_value_declaration(type, result, source)}
        ${_value_declaration(%("List"), temporary, converted)}
        @assignments (stmnt $result_expr)));
    }
  }
  return ast;
}
static List _return(Compiler compiler, List ast) {
  match (ast)
    case %(return ?rtype ?expression):
      return %(return ${compiler.convert_expression(expression, rtype)});
  return ast;
}

// (match expr ((pattern body) ...))
static List _match_cases(Compiler compiler, List ast) {
  List (expr, cases) = ast.cdr();
  expr = compiler.convert_expression(expr, %("List"));
  Array values = [];
  foreach (List rec, cases) {
    if (rec.car() == <preproc>) values.push(rec);
    else
      values.push(%(${compiler.match_pattern_binders(rec.car(), NULL)} @rec));
  }
  List result = values.list_free();
  return %(matchcases $expr $result);
}

// operator passes

static List _comparison(
  Compiler compiler, List ast, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type lhs_type) = lhs;
  (Var rhs_tag, Type rhs_type) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  if (!compiler.sym.is_var_type(lhs_type) &&
      !compiler.sym.is_var_type(rhs_type)) {
    if (op == <===>) return %(op == $lhs $rhs);
    if (op == <!==>) return %(op != $lhs $rhs);
    return ast;
  }
  lhs = compiler.convert_expression(lhs, %("Var"));
  rhs = compiler.convert_expression(rhs, %("Var"));
  switch (op) {
    case <==>:  return %(call "Var_equal" (args $lhs $rhs));
    case <!=>:  return %(expr (int)
                          (op ! (call "Var_equal" (args $lhs $rhs))));
    case <===>: return %(call "Var_same" (args $lhs $rhs));
    case <!==>: return %(expr (int)
                          (op ! (call "Var_same" (args $lhs $rhs))));
  }
  List call = %(call "Var_compare" (args $lhs $rhs));
  List zero = %(expr (int) (literal (int) "0"));
  return %(expr (int) (op $op $call $zero));
}

/* The dynamic binary operators are exactly those with a compound assignment
   spelling; `Var_binary` and `Var_update` accept the same operators. */
static int _dynamic_binary_operator(Symbol op) =>
  op.compound_assignment() != 0;

static int _raw_string_type(Type type) {
  type = type ? type.canonicalize() : NULL;
  return type && type.match(%((!or (dim *) (!quote *)) char));
}

static int _string_operand(Compiler compiler, Type type) =>
  compiler.sym.is_string_type(type)
      || _raw_string_type(type);

// Identify only the built-in helper family. Protocol resolution still
// handles every bracket form.
static Symbol _indexed_builtin_helper(Compiler compiler, Type type) {
  if (compiler.sym.is_array_type(type)) return <array>;
  if (compiler.sym.is_map_type(type)) return <map>;
  return 0;
}

// Helper-backed indexes bypass getindex lowering.
static int _indexed_parts(
  Compiler compiler, List expr, Symbol &owner, List &base, List &selector) {
  match (expr)
    case %(expr ? (getindex (!set ?matched_base (expr ?type ?))
                            ?matched_selector)): {
      owner = _indexed_builtin_helper(compiler, type);
      base = matched_base;
      selector = matched_selector;
      return 1;
    }
  return 0;
}

static void _convert_indexed_parts(
  Compiler compiler, Symbol owner, List &base, List &selector) {
  if (owner == <array>) {
    base = compiler.convert_expression(base, %("Array"));
    selector = compiler.convert_expression(selector, %(int));
  }
  else {
    base = compiler.convert_expression(base, %("Map"));
    selector = compiler.convert_expression(selector, %("Var"));
  }
}

static int _indexed_rhs_allowed(Compiler compiler, Symbol op, List rhs) {
  Type type = rhs.cadr();
  if (compiler.sym.is_var_type(type)) return 1;
  if (compiler.sym.resolve_numeric_type(type)) return 1;
  return op == <+> && _string_operand(compiler, type);
}

// Preserve x2c source order across C's unspecified call-argument order.
static List _sequenced_protocol_call(
  Compiler compiler, List resolved, List arguments) {
  (List binding, Type signature) = resolved;
  List parameters = signature.car().list().cadr();
  Type result = signature.cdr(), Array converted = [];
  for (List actual = arguments, expected = parameters;
       actual && expected;
       actual = actual.cdr(), expected = expected.cdr()) {
    List value = compiler.convert_expression(actual.car(), expected.car());
    /* A C macro such as raylib's WHITE expands to an expression x2c has no
       type for, and the sequencing temporary still has to declare one. The
       parameter's type is the type the value is about to be passed as. */
    (Var expr_tag, Type value_type, Var body) = value;
    (void) expr_tag;
    if (!value_type) value = %(expr ${expected.car()} $body);
    converted.push(value);
  }
  Array declarations = [], arguments_out = [];
  foreach (List value, converted) {
    Type type = value.cadr();
    List temporary = compiler.sym.introduce(
      compiler.fresh_name("protocol_arg"));
    declarations.push(_value_declaration(type, temporary, value));
    arguments_out.push(%(expr $type (ident $temporary)));
  }
  converted.free();
  List call = %(expr $result (call (expr $signature (ident $binding))
    (args @{arguments_out.list_free()})));
  return %(parens (block @{declarations.list_free()} (stmnt $call)));
}

static List _indexed_update(
  Compiler c, List lhs, Symbol op, List rhs) {
  Symbol owner, List base, selector;
  if (!_indexed_parts(c, lhs, owner, base, selector)) return NULL;
  (Var base_tag, Type base_type) = base;
  (void) base_tag;
  List resolved = c.resolve_protocol_member(base_type, "updateindex");
  if (!resolved) {
    String type = base_type.repr();
    c.report_error(
      <xform>, %"type $type does not support indexed compound assignment",
      NULL, NULL);
  }
  if (owner && !_indexed_rhs_allowed(c, op, rhs)) {
    (Var rhs_tag, Type rhs_type) = rhs;
    (void) rhs_tag;
    String details = %"right type: ${rhs_type.repr()}";
    String message = op == <+>
      ? "indexed += requires a numeric, Var, or String operand"
      : "indexed compound assignment requires a numeric or Var operand";
    c.report_error(<xform>, message, NULL, %($details));
  }

  if (!owner)
    return _sequenced_protocol_call(
      c, resolved,
      %($base $selector ${_symbol_expression(op)} $rhs));

  _convert_indexed_parts(c, owner, base, selector);
  rhs = c.convert_expression(rhs, %("Var"));
  String helper = owner == <array> ? "Array_updateindex" : "Map_updateindex";
  return %(
    call $helper (args $base $selector ${_symbol_expression(op)} $rhs));
}

static List _indexed_postfix(
  Compiler compiler, List arg, Symbol op) {
  Symbol owner, List base, selector;
  if (!_indexed_parts(compiler, arg, owner, base, selector)) return NULL;
  (Var base_tag, Type base_type) = base;
  (void) base_tag;
  List resolved =
    compiler.resolve_protocol_member(base_type, "postfixindex");
  if (!resolved) {
    String type = base_type.repr();
    compiler.report_error(
      <xform>, %"type $type does not support indexed increment or decrement",
      NULL, NULL);
  }
  if (!owner)
    return _sequenced_protocol_call(
      compiler, resolved,
      %($base $selector ${_symbol_expression(op)}));
  _convert_indexed_parts(compiler, owner, base, selector);
  String helper = owner == <array> ? "Array_postfixindex" : "Map_postfixindex";
  return %(call $helper (args $base $selector ${_symbol_expression(op)}));
}

static List _indexed_prefix(Compiler compiler, List arg, Symbol op) {
  List one = %(expr (int) (literal (int) "1"));
  Symbol binary = op == <++> ? <+> : <->;
  return _indexed_update(compiler, arg, binary, one);
}

static List _dynamic_binary(
  Compiler c, List ast, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type lhs_type) = lhs;
  (Var rhs_tag, Type rhs_type) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  int lhs_is_var = c.sym.is_var_type(lhs_type);
  int rhs_is_var = c.sym.is_var_type(rhs_type);
  if (!lhs_is_var && !rhs_is_var) return ast;
  int string_plus = op == <+>
                 && (lhs_is_var || _string_operand(c, lhs_type))
                 && (rhs_is_var || _string_operand(c, rhs_type));
  if (!string_plus &&
      ((!lhs_is_var && !c.sym.resolve_numeric_type(lhs_type)) ||
       (!rhs_is_var && !c.sym.resolve_numeric_type(rhs_type)))) {
    String left_type = lhs_type.repr(), right_type = rhs_type.repr();
    String details =
      %"operator: $op left type: $left_type right type: $right_type";
    c.report_error(
      <xform>, "dynamic numeric operators require numeric operands",
      NULL, %($details));
  }
  lhs = c.convert_expression(lhs, %("Var"));
  rhs = c.convert_expression(rhs, %("Var"));
  return %(call "Var_binary" (args $lhs ${_symbol_expression(op)} $rhs));
}

/* One protocol-member update. `x += y`, `++x`, and `x++` all resolve the
   operator's member on the receiver type, convert the right operand to the
   member's declared parameter, and ask for the update helper. A null `rhs`
   is a postfix update, which reads the receiver before the helper runs.
   The converted operand stays in `*rhs` when no helper exists, so a caller
   continues into the dynamic path with the operand it already built. */
static List _update_call(List target, List operator, List value,
                         String helper) {
  Type type = target.cadr();
  List address = %(expr ${type.reference()} (op & (parens $target)));
  return value ? %(call $helper (args $address $operator $value))
               : %(call $helper (args $address $operator));
}

static List _protocol_update(
  Compiler c, Type type, Symbol op, List arg, List &?rhs, Symbol spelled) {
  Symbol member = c.operator_member(op);
  if (!member) return NULL;
  String member_name = member;
  List resolved = c.resolve_protocol_member(type, member_name);
  if (!resolved) return NULL;
  if (rhs) {
    List converted = NULL;
    match (resolved)
      case %(? ((func (? ?parameter *)) ?)):
        converted = c.convert_expression(rhs, parameter);
    if (!converted) return NULL;
    rhs = converted;
  }
  String helper = c.protocol_update_helper(type, member_name, !rhs);
  if (!helper) return NULL;
  List spell = _symbol_expression(spelled);
  if (!rhs) return _update_call(arg, spell, NULL, helper);
  List value = rhs;
  return _update_call(arg, spell, value, helper);
}

static List _dynamic_compound(
  Compiler c, List ast, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type lhs_type) = lhs;
  (Var rhs_tag, Type rhs_type) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  int lhs_is_var = c.sym.is_var_type(lhs_type);
  int rhs_is_var = c.sym.is_var_type(rhs_type);
  if (_indexed_builtin_helper(c, lhs_type)) {
    String type = lhs_type.repr();
    c.report_error(
      <xform>, %"container type $type does not support compound assignment",
      NULL, %("update an indexed element instead"));
  }
  /* Without this rejection a nonmatching String compound falls through to
     native pointer arithmetic on an interned String. Concatenation itself
     lowers through the protocol member below like any adopter, resolved
     against canonical String because Var(String) adoption is exact while
     String typedefs still spell the same lvalue. */
  Type member_type = lhs_type;
  if (c.sym.is_string_type(lhs_type)) {
    if (op != <+> || !_string_operand(c, rhs_type))
      c.report_error(
        <xform>, "String compound assignment supports only String +=",
        NULL, NULL);
    member_type = %("String");
  }
  if (!lhs_is_var) {
    List updated = _protocol_update(c, member_type, op, lhs, rhs, op);
    if (updated) return updated;
    (rhs_tag, rhs_type) = rhs;
  }
  if (!lhs_is_var && !rhs_is_var) return ast;
  if (lhs_type.is_bitfield())
    c.report_error(
      <xform>, "dynamic compound assignment cannot target a bitfield",
      NULL, NULL);
  int rhs_allowed = rhs_is_var
                 || c.sym.resolve_numeric_type(rhs_type)
                 || (op == <+> && _string_operand(c, rhs_type));
  if (!rhs_allowed) {
    String details = %"right type: ${rhs_type.repr()}";
    c.report_error(
      <xform>,
      op == <+>
        ? "dynamic += requires a numeric, Var, or String operand"
        : "dynamic compound assignment requires a numeric or Var operand",
      NULL, %($details));
  }

  String helper = "x2c_var_update_volatile";
  if (!lhs_is_var) {
    Type scalar = c.sym.resolve_numeric_type(lhs_type);
    if (scalar && scalar.is_enum())
      c.report_error(
        <xform>, "dynamic compound assignment cannot target an enum",
        NULL, NULL);
    helper = scalar ? scalar.var_numeric_update_helper() : NULL;
    if (!helper) {
      String details = %"left type: ${lhs_type.repr()}";
      c.report_error(
        <xform>, "dynamic compound assignment requires a numeric lvalue",
        NULL, %($details));
    }
  }

  rhs = c.convert_expression(rhs, %("Var"));
  return _update_call(lhs, _symbol_expression(op), rhs, helper);
}

static List _operator(Compiler c, List ast) {
  List truthy = _truthy(c, ast);
  if (truthy != ast) return truthy;
  match (ast) {
    case %(op ?operator (!set ?lhs (expr ? ?))
             (!set ?rhs (expr ? ?))): {
      Symbol compound = Symbol.compound_operator(operator);
      if (compound) {
        List indexed = _indexed_update(
          c, lhs, compound, rhs);
        if (indexed) return indexed;
        return _dynamic_compound(
          c, ast, compound, lhs, rhs);
      }
      switch (operator.symbol()) {
        case <=>:
          return _assignment(
            c, operator, lhs, rhs);
        case <==>:  case <!=>:  case <===>: case <!==>:
        case <"<">: case <"<=">: case <">">:  case <">=">:
          return _comparison(
            c, ast, operator, lhs, rhs);
      }
      if (_dynamic_binary_operator(operator))
        return _dynamic_binary(
          c, ast, operator, lhs, rhs);
      return ast;
    }
    case %(op (!set ?operator (!or + - ~))
             (!set ?argument (expr ?argument_type ?))): {
      if (c.sym.is_var_type(argument_type))
        c.report_error(
          <xform>, "dynamic unary numeric operators are not supported",
          NULL, %("use Var.binary with an explicit numeric operand"));
      return ast;
    }
    case %(op (!set ?operator (!or ++ --))
             (!set ?argument (expr ?argument_type ?))): {
      Type type = argument_type, List arg = argument;
      List indexed = _indexed_prefix(c, arg, operator);
      if (indexed) return indexed;
      if (!c.sym.is_var_type(type)) {
        Symbol binary = operator == <++> ? <+> : <->;
        List one = %(expr (int) (literal (int) "1"));
        List updated = _protocol_update(c, type, binary, arg, one, binary);
        if (updated) return updated;
      }
      if (c.sym.is_var_type(type)) {
        List one = %(expr (int) (literal (int) "1"));
        one = c.convert_expression(one, %("Var"));
        Symbol binary = operator == <++> ? <+> : <->;
        return _update_call(
          arg, _symbol_expression(binary), one, "x2c_var_update_volatile");
      }
      return ast;
    }
  }
  return ast;
}

static List _postfix(Compiler compiler, List ast) {
  match (ast)
    case %(postfix ?operator
                   (!set ?argument (expr ?argument_type ?))): {
      Symbol op = operator, List arg = argument;
      Type type = argument_type;
      List indexed = _indexed_postfix(compiler, arg, op);
      if (indexed) return indexed;
      if (!compiler.sym.is_var_type(type)) {
        Symbol binary = op == <++> ? <+> : <->;
        List updated =
          _protocol_update(compiler, type, binary, arg, NULL, op);
        if (updated) return updated;
      }
      if (compiler.sym.is_var_type(type)) {
        List address = %(expr (* "Var") (op & (parens $arg)));
        return %(call "x2c_var_postfix_volatile"
                      (args $address ${_symbol_expression(op)}));
      }
      return ast;
    }
  return ast;
}

static List _truthy(Compiler compiler, List ast) {
  match (ast) {
    case %(if ?condition *body):
      return %(if ${_truthy_expression(compiler, condition)} @body);
    case %(while ?condition ?body):
      return %(while ${_truthy_expression(compiler, condition)} $body);
    case %(do ?body ?condition):
      return %(do $body ${_truthy_expression(compiler, condition)});
    case %(for ?init ?condition ?increment ?body):
      return %(for $init ${_truthy_expression(compiler, condition)}
                   $increment $body);
    case %(op (!set ?operator (!or && ||)) ?lhs ?rhs): {
      List left = _truthy_expression(compiler, lhs);
      List right = _truthy_expression(compiler, rhs);
      return %(op $operator $left $right);
    }
    case %(op ? ?condition ?ontrue ?onfalse):
      return %(op ? ${_truthy_expression(compiler, condition)}
                   $ontrue $onfalse);
    case %(op ! ?condition):
      return %(op ! ${_truthy_expression(compiler, condition)});
  }
  return ast;
}

// collection passes

// Normalize cons nodes so head and tail carry expected runtime types.
static List _cons(Compiler compiler, List ast) {
  List (head, tail) = ast.cdr();
  head = compiler.convert_expression(head, %("Var"));
  tail = compiler.convert_expression(tail, %("List"));
  return %(cons $head $tail);
}

/* A literal element is a `Var`, and an empty brace there is an empty Map. */
static List _literal_element(Compiler c, List element) {
  if (element.match(%(expr ? (composite (commas)))))
    element = %(expr ("Map") (map));
  return c.convert_expression(element, %("Var"));
}

/** Converts an `(array ...)` or `(varray ...)` node to source-ordered
    `(varray ...)` form, converting every typed element to `Var`.
*/
List transform_array_literal(Compiler compiler, List ast) {
  Array values = [];
  foreach (List elem, ast.cdr())
    values.push(_literal_element(compiler, elem));
  return %(varray @{values.list_free()});
}

/** Converts a `(map ...)` or `(vmap ...)` node to source-ordered
    `(vmap (vpair ...))` form, converting every typed key and value to
    `Var`.
*/
List transform_map_literal(Compiler compiler, List ast) {
  List elems = ast.cdr(), Array values = [];
  foreach (List entry, elems) {
    List (key, val) = entry.cdr();
    values.push(
      %(vpair ${_literal_element(compiler, key)}
              ${_literal_element(compiler, val)}));
  }
  List velems = values.list_free();
  return %(vmap @velems);
}

static List _append(Compiler compiler, List ast) {
  List (lhs, rhs) = ast.cdr();
  if (compiler.sym.is_var_type(lhs.cadr()))
    lhs = %(expr ("List") (call "Var_list" (args $lhs)));
  else lhs = compiler.convert_expression(lhs, %("List"));
  return %(append $lhs $rhs);
}

// string passes

static List _process_raw_segment(Compiler compiler, List seg) {
  String raw = seg.cadr(), literal = %"\"${raw.escape()}\"";
  List constructor = compiler.sym.reference(%("String_new"), NULL);
  return %(expr ("String") (call
           (expr ((func ((* char))) "String") (ident $constructor))
           (args (expr (* char) (literal $literal)))));
}

static List _build_cons_list(List list) {
  if (!list) return %(nil);
  List head = list.car(), tail = _build_cons_list(list.cdr());
  return %(cons $head $tail);
}

static List _string_segments(Compiler compiler, List ast) {
  /* A lone constant segment is already the whole string. Reuse the parsed
     literal's cache slot instead of joining a one-element List at runtime.
     Macro-generated literals arrive in this shape. Raise details are
     excluded: their cache slots would fill inside _file_init_ constructors,
     where re-entrant string-pool bootstrap can hand back NULL Strings. */
  match (ast) {
    case %(segments (segexp (expr ("String") (literal ("String") ?text)))):
      if (!compiler.runtime_literals)
        return compiler.cache(
          %(string (expr ("String") (literal ("String") $text))));
  }
  Array values = [];
  foreach (List seg, ast.cdr()) {
    Symbol kind = seg.car();
    switch (kind) {
      case <segraw>: seg = _process_raw_segment(compiler, seg);
        break;
      case <segvar>:
      case <segexp>:
        seg = compiler.convert_segment_to_string(seg.cadr());
        break;
      case <cache>: seg = %(expr ("String") $seg); break;
    }
    seg = compiler.convert_expression(seg, %("Var"));
    values.push(seg);
  }
  int segment_count = values.len();
  List segments = values.list_free();
  // Keep nested cons expressions below host-C bracket-depth limits.
  if (segment_count <= 128) {
    segments = _build_cons_list(segments);
    return %("String_join(NULL, " (expr ("List") $segments) ")");
  }
  String count = %"${segment_count}U";
  Type signature = NULL;
  List binding = compiler.sym.reference(%("List_list_n"), signature);
  List list = %(expr ("List")
    (call (expr $signature (ident $binding))
          (args (expr (unsigned) (literal (unsigned) $count)) @segments)));
  return %("String_join(NULL, " $list ")");
}

// Look through the `(at N ...)` anchors a node arrived wrapped in.
// Every block statement carries one so that a transform-phase diagnostic
// can name its line. A pass that dispatches on a statement tag has to see
// the statement, not the anchor.
static List _without_origin(List ast) {
  while (ast) {
    match (ast) {
      case %(at ? ?inner): ast = inner;
      default: return ast;
    }
  }
  return ast;
}

// Put a replacement statement back under the anchors of the statement it
// replaces, so a rewrite does not lose the node's source position.
static List _rewrap_origin(List original, List replacement) {
  match (original)
    case %(at ?origin ?inner):
      return %(at $origin ${_rewrap_origin(inner, replacement)});
  return replacement;
}

// defer passes

static int _defer_needs_landing(List ast) {
  if (!ast) return 0;
  match (ast)
    case %((!or return break continue goto try catchcases
                 match matchcases) *): return 1;
  foreach (Var child, ast)
    if (child is <list> && _defer_needs_landing(child)) return 1;
  return 0;
}

// File-static cleanup thunks cannot name block-local or variably-sized types.
// Keep the existing landing-frame lowering for those uncommon cases.
static int _defer_type_hoistable(Compiler compiler, Type type) {
  if (!type) return 0;
  Type flat = type.flatten_all();
  if (<register> in flat || <dim> in flat) return 0;
  Type base = type.base_type();
  if (!base) return 0;
  Var first = base.car();
  if (first is <string>) return compiler.sym.get(%($first)) != NULL;
  if (first == <struct> || first == <union> || first == <enum>)
    return base.len() == 2 && compiler.sym.get(base) != NULL;
  return 1;
}

static List _defer_direct_binding(Var value) {
  if (value is not <list>) return NULL;
  List ast = value;
  match (ast) {
    case %(ident ?binding): return binding;
    case %(expr ? ?inner):  return _defer_direct_binding(inner);
    case %(parens ?inner):  return _defer_direct_binding(inner);
    case %(op . ?inner *):  return _defer_direct_binding(inner);
  }
  return NULL;
}

static void _defer_collect_captures(
  Compiler compiler, List ast, List &declared, Map captures, Array records,
  List &written, int &unsupported) {
  if (!ast || unsupported) return;
  match (ast)
    case %(bind ?bound *): {
      List binding = bound, known = declared;
      if (!known.contains(binding)) declared = cons(binding, known);
    }
  match (ast)
    case %(expr ? (ident ?bound)): {
      List binding = bound;
      Var automatic, existing, stored_type;
      if (binding && !declared.contains(binding) &&
          compiler.semantic_binding_facts().try_get(
            %(automatic $binding), automatic) &&
          !captures.try_get(binding, existing)) {
        stored_type = compiler.semantic_binding_facts()[%(type $binding)];
        if (!_defer_type_hoistable(compiler, stored_type)) {
          unsupported = 1;
          return;
        }
        String field_name = compiler.fresh_name("defer_capture");
        List field = compiler.sym.introduce(field_name);
        captures[binding] = field;
        records.push(%($binding $stored_type $field));
      }
      return;
    }
  List modified = NULL;
  match (ast) {
    case %(op ?operator ?target *):
      if (operator is <symbol> && ast_changes_left_operand(operator))
        modified = _defer_direct_binding(target);
    case %(postfix ? ?target): modified = _defer_direct_binding(target);
  }
  foreach (Var child, ast)
    if (child is <list>)
      _defer_collect_captures(
        compiler, child, declared, captures, records, written,
        unsupported);
  Var field;
  List changed = written;
  if (modified && captures.try_get(modified, field) &&
      !changed.contains(modified))
    written = cons(modified, changed);
}

// Replace captured object references with pointer dereferences through the
// thunk environment. Expression types remain the source expression's type.
static List _defer_rewrite_captures(
  List ast, Map captures, List written, String env_name) {
  if (!ast) return ast;
  match (ast)
    case %(expr ?captured_type (ident ?bound)): {
      List binding = bound;
      Var field_var;
      if (captures.try_get(binding, field_var)) {
        String field_name = binding_identity_spelling(field_var);
        Type type = captured_type, target = type;
        if (binding in written &&
            !type.flatten_all().contains(<volatile>))
          target = cons(<volatile>, type);
        Type pointer = cons(<*>, target);
        String reference = %"$env_name->$field_name";
        List source = %(expr (* const void) $reference);
        List cast = %(expr $pointer (cast $pointer $source));
        List dereference = %(expr $type (op * $cast));
        return %(expr $type (parens $dereference));
      }
      return ast;
    }
  List child;
  $ast.rewrite_children(ast, child,
    _defer_rewrite_captures(child, captures, written, env_name));
}

static List _lower_callable_defer(
  Compiler c, List body, List finalizer) {
  List declared = %(), written = %();
  Map captures = {}, Array records = [], int unsupported = 0;
  _defer_collect_captures(
    c, finalizer, declared, captures, records, written, unsupported);
  if (unsupported) {
    records.free();
    return %(try $body () $finalizer);
  }

  List env_binding = NULL, env_local = NULL, String env_name = NULL;
  List record_list = records.list_free();
  if (record_list) {
    env_name = c.fresh_name("defer_env");
    env_binding = c.sym.introduce(env_name);
    env_local = c.sym.introduce(c.fresh_name("defer_data"));
    Array fields = [];
    foreach (List record, record_list) {
      List field = record.caddr();
      fields.push(%(declare (const void) (bindings (bind $field (*)))));
    }
    List env_type = %(
      typedef (struct $env_name (fields @{fields.list_free()}))
              (bindings (bind $env_binding ()))
    );
    c.add_early(env_type);
  }

  List opaque = c.sym.introduce(c.fresh_name("defer_opaque"));
  List callback = c.sym.introduce(c.fresh_name("defer_cleanup"));
  String env_local_name = env_local
                        ? binding_identity_spelling(env_local) : NULL;
  List rewritten = env_local_name
                 ? _defer_rewrite_captures(
                   finalizer, captures, written, env_local_name)
                 : finalizer;
  List setup = NULL;
  if (env_binding) {
    List opaque_expr = %(expr (* void) (ident $opaque));
    List cast = %(expr (* $env_name) (cast (* $env_name) $opaque_expr));
    setup = %(declare ($env_name)
              (bindings (op = (bind $env_local (*)) $cast)));
  }
  List callback_body = setup
                     ? %(block $setup $rewritten)
                     : %(block $rewritten);
  List callback_bind = %(
    bind $callback
      ((fnmod (params (param (void) (bind $opaque (*))))))
  );
  List callback_func = %(
    function (static void) $callback_bind $callback_body);
  c.add_early(callback_func);
  if (c.fn_name)
    c.semantic_binding_facts()[%(defer-ownr $callback)] =
      c.fn_name;

  return %(defer $body $env_binding $callback $record_list $written);
}

// Choose the callable chain for ordinary cleanup statements and retain the
// landing-frame path for lexical transfers or unsupported capture types.
static List _lower_defer_region(
  Compiler compiler, List body, List finalizer) {
  if (compiler.source_map && compiler.origin)
    finalizer = %(at ${compiler.origin} $finalizer);
  if (_defer_needs_landing(finalizer))
    return %(try $body () $finalizer);
  return _lower_callable_defer(compiler, body, finalizer);
}

static List _rewrite_defer_list(Compiler compiler, List stmts) {
  if (!stmts) return stmts;
  int has_defer = 0;
  foreach (List statement, stmts) {
    List head = _without_origin(statement);
    match (head) case %(defer ?): has_defer = 1;
    if (has_defer) break;
  }
  if (!has_defer) return stmts;
  Array suffixes = $auto([]);
  for (List suffix = stmts; suffix; suffix = suffix.cdr())
    suffixes.push(suffix);
  List result = stmts;
  int tail_changed = 0;
  for (int i = (int) suffixes.len() - 1; i >= 0; i--) {
    List suffix = suffixes[i];
    List anchored = suffix.car();
    List tail = tail_changed ? result : suffix.cdr();
    List head = _without_origin(anchored);
    match (head) case %(defer ?final_stmt): {
      List body = %(block @tail), finalizer = final_stmt;
      if (compiler.source_map)
        finalizer = _rewrap_origin(anchored, finalizer);
      List region = _lower_defer_region(compiler, body, finalizer);
      result = %( ${_rewrap_origin(anchored, region)} );
      tail_changed = 1;
      continue;
    }
    if (tail_changed) result = cons(anchored, result);
  }
  return result;
}

static int _raise_detail_type_allowed(Compiler compiler, Type type) {
  if (!type) return 0;
  with compiler.sym {
    if (_.is_var_type(type) ||
        _.is_string_type(type) ||
        _.is_named_value_type(type, "List") ||
        _.is_named_value_type(type, "Symbol") ||
        _.is_named_value_type(type, "Atom"))
      return 1;
    return !!_.resolve_numeric_type(type);
  }
}

static Type _raise_nested_invalid_type(Compiler compiler, Var node) {
  if (node is not <list>) return NULL;
  List ast = node;
  match (ast)
    case %(expr ?expr_type ?value): {
      Type type = expr_type;
      if (!_raise_detail_type_allowed(compiler, type)) return type;
      if (compiler.sym.is_var_type(type)) {
        List payload = value;
        match (payload)
          case %(call ?(String callee) ?arguments):
            if (callee.endswith("_var"))
              return _raise_nested_invalid_type(compiler, arguments);
        return NULL;
      }
      if (!compiler.sym.is_named_value_type(type, "List")) return NULL;
      return _raise_nested_invalid_type(compiler, value);
    }
  foreach (Var child, ast) {
    Type invalid = _raise_nested_invalid_type(compiler, child);
    if (invalid) return invalid;
  }
  return NULL;
}

static List _raise(
  Compiler compiler, List ast, Var cause, List arguments) {
  Array values = [], int index = 0;
  List code = compiler.convert_expression(cause, %("Symbol"));
  int changed = code != cause;
  foreach (List value, arguments) {
    Type invalid = NULL;
    if (index & 1) value = compiler.promote_string_literal(value);
    if (index & 1)
      match (value)
        case %(expr ?value_type ?content): {
          Type type = value_type;
          if (!_raise_detail_type_allowed(compiler, type)) invalid = type;
          else if (compiler.sym.is_named_value_type(type, "List"))
            invalid = _raise_nested_invalid_type(compiler, content);
        }
    if (invalid) {
      String message = %"raise detail type ${invalid.repr()} is not immutable";
      List location = compiler.origin_location(compiler.origin);
      compiler.diagnostics.report(
        <type>, message, location,
        %("use a numeric value, enum, Symbol, Atom, String, List, or Var"));
      // Null replaces the reported detail, so a later pass never sees it.
      value = %(expr ("Var") (call "Var_null" (args)));
    }
    List converted = compiler.convert_expression(value, %("Var"));
    if (converted != value) changed = 1;
    values.push(converted);
    index++;
  }
  if (!changed) {
    values.free();
    return ast;
  }
  List converted = values.list_free();
  return %(raise $code (args @converted));
}

// Lower bracket reads into helper calls with method-call conversions.
static List _nominal_getindex(Compiler compiler, Type type) {
  if (!type.is_typedef_name()) return NULL;
  if (compiler.sym.is_array_type(type) ||
      compiler.sym.is_map_type(type))
    return NULL;
  match (type)
    case %(?(String nominal)): {
      String source = %"${nominal}_getindex";
      Type signature = compiler.sym.get(%($source));
      match (signature)
        case %((func ($type ?)) ?):
          return %(${compiler.sym.reference(%($source), NULL)}
                   $signature);
    }
  return NULL;
}

static List _cast(Compiler compiler, List ast) {
  match (ast)
    case %(cast (!set ?declarator (decl *parts))
                (!set ?expression (expr ?source_type ?))): {
    List declaration = %(declare @parts);
    Type type = declaration.type_from_ast();
    List operand = expression;
    if (operand.match(%(expr ? (composite *)))) {
      Type native = type;
      match (declaration)
        case %(declare ?base (bindings (bind ? ?mods))):
          native = mods.list().append(base);
      return compiler.convert_compound_literal(operand, type, native);
    }
    int source_var = compiler.sym.is_var_type(source_type);
    int target_var = compiler.sym.is_var_type(type);
    int unresolved = 0;
    match (expression)
      case %(expr () (ident ?)): unresolved = 1;
    int target_func = source_type &&
      compiler.sym.resolve_key(type) === compiler.sym.resolve_key(%("Func"));
    if (type !== %(void) &&
        (source_var || target_func ||
         (target_var && (source_type || unresolved))))
      return compiler.convert_expression(expression, type);
    return %(cast $type $expression);
  }
  match (ast)
    case %(cast ?target (!set ?value (expr ? (composite *)))):
      return compiler.convert_compound_literal(value, target, target);
  return ast;
}

// transform driver

static List _match_records(Compiler compiler, List records) {
  Array transformed = [];
  foreach (List record, records)
    match (record) {
      case %(preproc ?): transformed.push(record);
      case %(*prefix ?body):
        transformed.push(%(@prefix ${_node(compiler, body)}));
    }
  return transformed.list_free();
}

/* Only top-level and block sequences absorb `(seq ...)` replacements.
   Children transform left to right, then reverse assembly preserves source
   order while allocating generated splice origins from right to left. */
static Ast _sequence(Compiler compiler, Ast ast) {
  Array transformed = $auto([]);
  foreach (List value, ast) {
    List source = _without_origin(value);
    List lowered = source.match(%(defer ?))
      ? value : _node(compiler, value);
    if (!compiler.fn_name) lowered = _cleanup_unit(compiler, lowered);
    transformed.push(lowered);
  }
  Ast tail = NULL;
  for (int i = (int) transformed.len() - 1; i >= 0; i--) {
    Ast node = transformed[i];
    List payload = _without_origin(node);
    match (node)
      case %(at ?parent ?):
        match (payload)
          case %(seq *items): {
            Array anchored = [];
            foreach (List item, items) {
              compiler.origins.push(%(generated $parent splice));
              int generated = compiler.origins.len();
              anchored.push(%(at $generated $item));
            }
            tail = anchored.list_free().append(tail);
            continue;
          }
    match (node)
      case %(seq *items): {
        tail = items.append(tail);
        continue;
      }
    tail = cons(node, tail);
  }
  return tail;
}

static Ast _children(Compiler compiler, Ast ast) {
  List child;
  $ast.rewrite_children(ast, child, _node(compiler, child));
}

/* Normalize synthesized sequences before their containing block absorbs
   pending defer markers. Matches retain their specialized record driver. */
static Ast _finish(Compiler compiler, Ast ast) {
  match (ast) {
    case %(seq *items):
      return %(seq @{_sequence(compiler, items)});
    case %(matchcases ?subject ?records): {
      List new_subject = _node(compiler, subject);
      List new_records = _match_records(compiler, records);
      return %(matchcases $new_subject $new_records);
    }
    case %(block *body): {
      List lowered = _sequence(compiler, body);
      List deferred = _rewrite_defer_list(compiler, lowered);
      if (deferred != lowered) lowered = _sequence(compiler, deferred);
      return %(block @lowered);
    }
  }
  return _children(compiler, ast);
}

/* A left-leaning operator chain nests one (expr (op ...)) level per source
   term, so child-first transformation would recurse once per term. Walk down
   the spine while each level survives its operator rewrites unchanged,
   transform the deepest term, and rebuild upward. Entered only for chain
   heads, with expression rewrites already applied. */
static Ast _op_chain(Compiler compiler, Ast ast) {
  Array levels = $auto([]);
  Array types = $auto([]);
  Ast rebuilt = NULL;
  for (;;) {
    List first = NULL;
    match (ast)
      case %(expr ? (op ? ?(List matched) *))
        if (matched.match(%(expr ? (op *)))):
          first = matched;
    if (!first) {
      rebuilt = _finish(compiler, ast);
      break;
    }
    Var type = ast.cadr();
    if (type is <list>) type = _node(compiler, type);
    List opnode = ast.caddr();
    List rewritten = _operator(compiler, opnode);
    if (rewritten != opnode) {
      rebuilt = %(expr $type ${_node(compiler, rewritten)});
      break;
    }
    types.push(type);
    levels.push(ast);
    ast = compiler.lower_typed_adapter_expr(first);
    ast = compiler.lower_lambda_expr(ast);
  }
  for (int i = (int) levels.len() - 1; i >= 0; i--)
    match (levels[i])
      case %(expr ? (op ?operator ? *rest)): {
        Array parts = [];
        if (operator is <list>) parts.push(_node(compiler, operator));
        else parts.push(operator);
        parts.push(rebuilt);
        foreach (Var operand, rest) {
          if (operand is <list>) parts.push(_node(compiler, operand));
          else parts.push(operand);
        }
        rebuilt = %(expr ${types[i]} (op @{parts.list_free()}));
      }
  return rebuilt;
}

/* Callers supply bound, typed canonical nodes, and transform helpers construct
   the normalized shapes consumed by the emitter. A helper rewrites only its
   current node: this dispatcher recurses into returned children, while
   _sequence alone splices `(seq ...)` results into a sequence. */
static Ast _step(Compiler c, Ast ast) {
  if (!ast) return NULL;
  match (ast)
    case %(managed-init ?):
      c.report_error(
        <parse>,
        "managed initializer requires a complete block-local initializer",
        NULL, NULL);
  Var head = ast.car();
  if (head is not <symbol>) return _children(c, ast);
  match (ast) {
    case %(at ?origin ?inner): {
      int occurrence = origin;
      List transformed = NULL;
      $let(c.origin, occurrence) {
        transformed = _node(c, inner);
      }
      if (transformed == inner) {
        return ast;
      }
      c.origins.push(%(generated $occurrence xform));
      int generated = c.origins.len();
      return %(at $generated $transformed);
    }
    case %(function ?return_type
           (!set ?declarator (bind ?binding ?)) ?body): {
      String owner = binding_identity_spelling(binding);
      Var stored_owner;
      if (c.semantic_binding_facts().try_get(
        %(defer-ownr $binding), stored_owner))
        owner = stored_owner;
      String previous = c.fn_name;
      int previous_inline = c.inline_header;
      c.fn_name = owner;
      Type function_type = return_type;
      c.inline_header = function_type.is_inline() &&
                        !function_type.is_static();
      List new_return = _node(c, return_type);
      List new_decl = _node(c, declarator);
      List prepared_body = _lower_lambda_destructuring(
        c, body);
      prepared_body = c.prepare_lambda_cells(
        declarator, prepared_body);
      List new_body = _node(c, prepared_body);
      List transformed = %(function $new_return
                           $new_decl $new_body);
      c.fn_name = previous;
      c.inline_header = previous_inline;
      return transformed;
    }
    case %(getindex
           (!set ?expression (expr ?matched_type ?)) ?index): {
      Type type = matched_type;
      List resolved = _nominal_getindex(c, type);
      if (!resolved) resolved = c.resolve_protocol_member(type, "getindex");
      if (!resolved)
        c.report_error(
          <xform>,
          %"type $type does not support bracket indexing", NULL, NULL);
      (List binding, Type signature) = resolved;
      return _node(
        c,
        %(call (expr $signature (ident $binding))
               (args $expression $index))
      );
    }
    case %(setindex
           (!set ?expression (expr ?matched_type ?)) ?index ?value): {
      Type type = matched_type;
      List resolved = c.resolve_protocol_member(type, "setindex");
      if (!resolved)
        c.report_error(
          <xform>,
          %"type $type does not support bracket assignment", NULL, NULL);
      if (!_indexed_builtin_helper(c, type))
        return _node(
          c,
          _sequenced_protocol_call(
            c, resolved, %($expression $index $value))
        );
      (List binding, Type signature) = resolved;
      return _node(
        c,
        %(call (expr $signature (ident $binding))
               (args $expression $index $value))
      );
    }
    case %(slice
           (!set ?expression
             (expr (!set ?matched_type (*)) ?))
           ?start ?stop ?step): {
      Type type = matched_type;
      String nominal = NULL;
      match (type)
        case %(?(String name)): nominal = name;
      if (!nominal)
        c.report_error(
          <xform>, %"type $type does not support slicing", NULL, NULL);
      String fnname = %"${nominal}_getslice";
      if (!c.sym.get(%($fnname)))
        c.report_error(
          <xform>,
          %"type $type does not support slicing", NULL, %());
      String none = "-2147483648";
      start = start ? start : %(literal (int) $none);
      stop = stop ? stop : %(literal (int) $none);
      step = step ? step : %(literal (int) "1");
      return _node(
        c,
        %(call "$fnname" (args $expression $start $stop $step)));
    }
  }
  Ast original = ast;
  switch (head.symbol()) {
    case <protocol>: case <adopt>: case <macrodef>: return ast;
    case <literal>:  return ast;
    case <expr>: ast = c.lower_typed_adapter_expr(ast);
      ast = c.lower_lambda_expr(ast);
      match (ast)
        case %(expr ? (op ? ?(List first) *))
          if (first.match(%(expr ? (op *)))):
            return _op_chain(c, ast);
      break;
    case <array>:    ast = transform_array_literal(c, ast);     break;
    case <map>:      ast = transform_map_literal(c, ast);       break;
    case <cast>:     ast = _cast(c, ast);             break;
    case <index>:    ast = _index(c, ast);            break;
    case <cons>:     ast = _cons(c, ast);             break;
    case <append>:   ast = _append(c, ast);           break;
    case <var>:      ast = _to_var(c, ast.cadr());    break;
    case <segments>: ast = _string_segments(c, ast);  break;
    case <declare>: case <decl>:
      ast = _declaration(c, ast);                     break;
    case <dstrdecl>:
      ast = _destructure_declaration(c, ast);        break;
    case <stmnt>:    ast = _destructure_statement(
      c,
      ast);     break;
    case <dstrasgn>:
      ast = _destructure_value(c, ast);              break;
    case <match>:    ast = _match_cases(c, ast);      break;
    case <defer>: {
      match (ast)
        case %(defer ?finalizer):
          ast = _lower_defer_region(c, %(block), finalizer);
      break;
    }
    case <raise>: {
      // Raise details intern at raise time, never in constructors.
      int old_runtime = c.runtime_literals;
      c.runtime_literals = 1;
      match (ast)
        case %(raise ?cause (args *arguments)):
          ast = _raise(c, ast, cause, arguments);
      ast = _children(c, ast);
      c.runtime_literals = old_runtime;
      return ast;
    }
    case <block>: {
      List statements = ast.cdr();
      List body = _rewrite_defer_list(c, statements);
      if (body !== statements) ast = %(block @body);
      break;
    }
    case <return>:   ast = _return(c, ast);           break;
    case <if>: case <while>: case <do>: case <for>:
      ast = _truthy(c, ast);                           break;
    case <call>:     ast = _call(c, ast);             break;
    case <op>:       ast = _operator(c, ast);         break;
    case <postfix>:  ast = _postfix(c, ast);          break;
  }
  if (ast != original) return _node(c, ast);
  return _finish(c, ast);
}

/* Normalize newly constructed syntax where it is produced. Children enter
   the same operation, so completed units do not require another unit walk. */
static Ast _node(Compiler c, Ast ast) {
  return _step(c, ast);
}

/** Lowers a bound and typed top-level AST to the normalized form consumed by
    emission. `compiler` must own the AST's bindings, origins, and conversion
    state. Current-node rewrites finish before child traversal; containing
    blocks absorb cleanup markers produced by declaration rewrites. Early
    declarations are lowered and appended after the input units. The call
    may add generated origins or diagnostics to `compiler`.
*/
List Compiler.transform(Compiler compiler, List ast) {
  /* Regions are read before lowering, while `$scope`, `$auto`, and the
     `defer` beside each region are still the forms the parser produced. */
  compiler.check_regions(ast);
  List newast = _sequence(compiler, ast);
  // Merge and lower synthesized lambda siblings.
  Array generated = [];
  while (compiler.early_decls.len()) {
    List items = compiler.early_decls;
    compiler.early_decls.clear();
    List lowered = _sequence(compiler, items);
    foreach (Var sibling, lowered) generated.push(sibling);
  }
  if (generated.len()) newast = newast.append(generated.list_free());
  return newast;
}

#endif
