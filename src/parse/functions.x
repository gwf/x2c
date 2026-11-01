/*  functions.x -- function definitions and lifecycle

    Copyright (c) 2025 Gary William Flake.
*/

// function definitions

/** Parses one function decorator target and returns its resulting AST.
    A compatible unit macro at the current token is expanded first; otherwise
    an ordinary function definition is required.
*/
List Compiler.parse_function_target(Compiler c) {
  List macro = c.try_parse_macro_target_at(<unit>);
  if (!macro) return c.parse_function_definition();
  return Ast.lone_item(macro);
}

/** Parses one function declaration and its required compound body.
    The parameter bindings are active while the body is parsed, and the first
    token after the closing brace remains current.
*/
List Compiler.parse_function_definition(Compiler c) {
  Token tokens = c.tokenizer.tokens, start = c.token;
  List declaration = c.parse_simple_declaration();
  if (c.peek(0) != <"{"> && !_x2c_at_function_arrow(c))
    $fail.parse_function_body(c, c.token);
  int first = start - tokens, body = c.token - tokens;
  List function = _finish_function(c, declaration, NULL);
  if (!c.macro_holes)
    _definition_source(c, function, start.line, NULL, $(first, body));
  return function;
}

/** The declared result type of the function `declaration`, which its
    `return` statements convert to, or NULL.
*/
Type Ast.declared_return(List declaration) {
  match (declaration.type_from_ast())
    case %((func *) *result): return result.type().declared();
  return NULL;
}

// function definitions and lifecycle

// Complete a token-parsed or generated function in its parameter scope.
module List _finish_function(
  Compiler c, List declaration, List syntax) {
  match (declaration)
    case %(declare ?rtype
           (bindings
             (!set ?declarator (bind ?binding ?)))):
      return _finish_function_parts(
        c, declaration, rtype, declarator, binding,
        syntax);
  return NULL;
}

static List _finish_function_parts(
  Compiler c, List declaration, List rtype, List declarator,
  List binding, List syntax) {
  defer {
    c.params.symbols = NULL;
    c.params.bindings = NULL;
    c.params.enumerators = NULL;
    c.params.macros = NULL;
  }
  /* Validate lifecycle ownership before the body, but publish `init_fn` and
     `fini_fn` only after the parameter scope and body finish successfully.
     A caller's `SymTxn` can still roll those names back if a later generated
     sibling fails. */
  String initializer_owner = NULL, shutdown_owner = NULL;
  String name = _prepare_lifecycle(
    c, declaration, binding, initializer_owner, shutdown_owner);
  List body = _function_body(c, declaration, name, syntax);
  if (initializer_owner) c.init_fn = name;
  if (shutdown_owner) c.fini_fn = name;
  return %(function $rtype $declarator $body);
}

/* The body parses, or a constructed body binds, in the parameter scope with
   the function's return type and name current. */
static List _function_body(
  Compiler c, List declaration, String name, List syntax) {
  int expression_body = !syntax && _x2c_at_function_arrow(c);
  if (!syntax && !expression_body) c.expect(<"{">);
  Type old_return = c.return_type;
  c.return_type = Ast.declared_return(declaration);
  String old_fn = c.fn_name;
  c.fn_name = name;
  c.sym.push_scope(c.params);
  int depth = c.ancestors.len(), placed = c.placements.len();
  c.enter((Ancestor){ .what = <function>, .node = declaration });
  List body = NULL;
  {
    // A failed body leaves no rows or placements of its own behind.
    defer {
      c.ancestors.truncate(depth);
      c.placements.resize(placed);
      c.sym.pop_scope();
      c.return_type = old_return;
      c.fn_name = old_fn;
    }
    if (syntax) body = c.bind_callable_body(syntax, c.return_type);
    else if (expression_body) body = _expression_body(c);
    else body = c.parse_callable_body();
    body = c.prepend_setup(body, _entry_code(c, depth));
  }
  return body;
}

static String _prepare_lifecycle(
  Compiler c, List declaration, List binding, String &initializer_owner,
  String &shutdown_owner) {
  String name = Ast.binding_spelling(binding);
  initializer_owner = name
    ? _lifecycle_owner(c, binding, "initialize") : NULL;
  shutdown_owner = name
    ? _lifecycle_owner(c, binding, "shutdown") : NULL;
  if (initializer_owner) {
    _require_signature(c, declaration, name, "initializer");
    if (c.init_fn && c.init_fn != name)
      $fail.parse_init_duplicate(c, c.token, name);
  }
  if (shutdown_owner) {
    _require_signature(c, declaration, name, "shutdown");
    if (c.fini_fn && c.fini_fn != name)
      $fail.parse_shutdown_duplicate(c, c.token, name);
  }
  return name;
}

static String _lifecycle_owner(
  Compiler c, List binding, String member) {
  List method = c.fact(%(method $binding));
  if (!method) return NULL;
  match (method)
    case %(?name $member): {
      String owner = name, Type owner_type = c.sym.get($(owner));
      return owner_type.is_typedef() ? owner : NULL;
    }
  return NULL;
}

static void _require_signature(
  Compiler c, List decl, String name, String role) {
  if (decl ~= %(declare (void)
                (bindings
                  (bind ?
                    ((fnmod (params (param (void) (bind () ())))))))))
    return;
  $fail.parse_lifecycle_signature(c, c.token, role, name);
}

static List _expression_body(Compiler c) {
  alias c {
    _.expect(<=>);
    _.expect(<">">);
    Token origin = _.token;
    _.sym.push_new_scope();
    List result = NULL;
    {
      defer _.sym.pop_scope();
      List expression = _.parse_expression();
      _.expect(<;>);
      /* A `void` result has no value to return, and C rejects a returned
         value there, so the expression stands as the body's statement. */
      with (_.token = origin) {
        result = _.return_type === %(void)
               ? %(stmnt $expression) : _.finish_return_statement(expression);
      }
    }
    return %(block $(_.anchor_origin(result, origin)));
  }
}

// constructed functions

/* Collection binds a constructed function's declaration and keeps its body
   (see `_collected_function`). The full parse binds the whole function
   under the macro stack that constructed it, as a declaration default. */
module List _bind_collected_function(
  Compiler c, List input, Var return_type, Var declarator, Var body,
  Var construction) {
  if (c.shallow) return input;
  Type type = %(declare $return_type (bindings $declarator)).type_from_ast();
  if (c.public_bodies &&
      (!type.is_inline() || type.is_static() || c.source_private)) return NULL;
  with (c.macro_stack = construction) {
    Token invocation = c.macro_stack ? c.macro_stack.last().list()[3] : NULL;
    with (c.origin = invocation ? c.record_origin(invocation) : c.origin) {
      return c.bind_syntax(
        %(function $return_type $declarator $body), <unit>, c.return_type);
    }
  }
}

/* Binds a constructed function's parameters in a fresh prototype scope,
   which becomes its parameter scope, and then its declaration. */
module List _bind_function(
  Compiler c, Var return_type, Var function_name, List parameter_values,
  List return_modifiers, Var body) {
  List parameter_list = _bind_parameters(c, parameter_values);
  List declarator = %(
    bind $function_name
      ((fnmod (params @parameter_list)) @return_modifiers)
  );
  List declaration = c.bind_syntax(
    %(declare $return_type (bindings $declarator)), <unit>, c.return_type);
  if (c.shallow) return _collected_function(c, declaration, body);
  Type type = declaration.type_from_ast();
  if (c.public_bodies &&
      (!type.is_inline() || type.is_static() || c.source_private)) return NULL;
  return _finish_function(c, declaration, body);
}

static List _bind_parameters(Compiler c, List values) {
  Array parameters = [];
  c.sym.push_new_scope();
  {
    defer c.params = c.sym.pop_scope();
    foreach (Var value in values)
      foreach (Var row in c.evaluate_macro_rows(value)) match (row) {
        case %(...): parameters.push(row);
        case %(param ?base (!set ?declarator (bind ? ?))):
          parameters.push(
            _finish_parameter(c, base, declarator, NULL, NULL, NULL));
      }
  }
  return parameters.list_free();
}

/* Collection publishes a constructed function's declaration and keeps its
   body for the full parse. */
static List _collected_function(
  Compiler c, List declaration, Var body) {
  c.record_inline_function(declaration);
  match (declaration)
    case %(declare ?type (bindings (bind ?binding ?modifiers))): {
      String name = Ast.binding_spelling(binding);
      // A static definition stays in its unit, as in source.
      if (type.type().is_static())
        c.sym.mark_static(%(function $name));
      else c.fn_defs[name] = 1;
      c.record_declaration_visibility(declaration);
      List method = c.fact(%(method $binding));
      if (method) {
        // Replay the resolved owner with this declaration's own member.
        String member = method.cadr();
        String owner = name[:name.len() - member.len() - 1];
        declaration = %(declare $type
          (bindings (bind (($owner) $member) $modifiers)));
      }
      else {
        /* Renamed locals keep their identity; exact names complete
           prototypes. */
        Var source;
        if (!c.semantic_binding_facts().try_get(
          %(source-spelling $binding), source) || source == name)
          declaration = %(declare $type (bindings (bind $name $modifiers)));
      }
    }
  return %(declaration-function $declaration $body $(c.macro_stack));
}
