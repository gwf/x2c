/*  syntax.x -- compile-time SDK syntax

    Copyright (c) 2026 Gary William Flake.
*/

static macro Stmt $fail.meta_sdk_binding_spelling(Expr $syntax) =>
  _reject_value(
    "Code.binding_spelling requires an identifier spelling", $syntax);

static macro Stmt $fail.meta_sdk_binding_syntax(Expr $syntax) =>
  _reject_value(
    "Code.binding_spelling requires binding syntax", $syntax);

static macro Stmt $fail.meta_sdk_binding_known(Expr $value) =>
  MetaContext.reject(
    "Code.binding_spelling requires a known binding",
    %("binding: $($value.repr())"));

static macro Stmt $fail.meta_sdk_binding_identifier(Expr $syntax) =>
  _reject_value(
    "Code.binding_spelling requires an identifier or binding", $syntax);

static macro Stmt $fail.meta_sdk_identifier(Expr $spelling) =>
  _reject_value(
    "x2c_ident requires an identifier spelling", $spelling);

static macro Stmt $fail.meta_sdk_binding_role(Expr $role) =>
  _reject_value("x2c_binding_fresh requires an identifier role", $role);

static macro Stmt $fail.meta_sdk_unique_stem(Expr $stem) =>
  _reject_value(
    "_x2c.name.unique requires an identifier stem", $stem);

static macro Stmt $fail.meta_sdk_parameter_missing(
  Expr $function, Expr $wanted) =>
  MetaContext.reject(
    %"Code.parameter cannot find '$($wanted)'",
    %("function: $(Code.name($function).repr())"));

static alias fail_constant to
  MetaContext.reject("captured code is not a compile-time constant", NULL);

static macro Stmt $fail.meta_sdk_enclosing_role(Expr $value) =>
  _reject_value(
    "x2c_enclosing names declarator, statement, function, or unit", $value);

// syntax queries

/** Reads a constant through the compiler's existing constant decoder. */
Var Code.value(Code code) {
  _require_expansion("Code.value");
  Compiler compiler = Compiler.expanding();
  if (code ~= %(expr ? (macro-value ?definition)))
    code = compiler.capture_macro_value(definition);
  Var value = compiler.folded_constant(code);
  if (value is void)
    fail_constant;
  return value;
}

/** Answers `Code.call_in_order`, declared in `lib/meta.x`. The call binds
    its temporaries here, so the result is a carrier that binds no
    further.
*/
Code Code.call_in_order(Code member, List arguments, Type type) {
  _require_expansion("Code.call_in_order");
  List call = active.expander.call_in_order(member, arguments);
  return Code.lowered(%(expr $type $call), NULL);
}

/** Answers `Code.lowered`, declared in `lib/meta.x`, with the carrier
    `Compiler.take_code_value` consumes.
*/
Code Code.lowered(Code c, List effects) => %(code-value "lowered" $c $effects);

/** Answers `Code.bound`, declared in `lib/meta.x`, with the carrier
    `Compiler.take_code_value` consumes.
*/
Code Code.bound(Code c, List effects) => %(code-value "bound" $c $effects);

/** Answers `Code.func_parameters`, declared in `lib/meta.x`. */
List Code.func_parameters(Code parameters, Code fn, Code argv) {
  _require_expansion("Code.func_parameters");
  return active.expander.func_parameters(parameters, fn, argv);
}

/** Answers `Code.exits`, declared in `lib/meta.x`. */
int Code.exits(Code statement) {
  _require_expansion("Code.exits");
  return Ast.reference_guard_exits(statement);
}

/** Answers `Code.convert`, declared in `lib/meta.x`. */
Code Code.convert(Code value, Type target) {
  _require_expansion("Code.convert");
  return active.expander.convert_expression(value, target);
}

/** Answers `Code.format`, declared in `lib/meta.x`. */
String Code.format(Code value) {
  _require_expansion("Code.format");
  return active.expander.printf_static_format(value);
}

/** Answers `Code.is_static_pattern`, declared in `lib/meta.x`. */
int Code.is_static_pattern(Code pattern) {
  _require_expansion("Code.is_static_pattern");
  return active.expander.match_pattern_is_static(pattern);
}

/** Answers `Code.pattern_value`, declared in `lib/meta.x`. */
Var Code.pattern_value(Code pattern) {
  _require_expansion("Code.pattern_value");
  return active.expander.match_pattern_value(pattern);
}

/** Answers `Code.promoted`, declared in `lib/meta.x`. */
Code Code.promoted(Code value) {
  _require_expansion("Code.promoted");
  return active.expander.promote_string_literal(value);
}

/** Returns an expression reading each binding `declaration` declares. */
List Code.declared_bindings(List declaration) {
  Array result = [];
  match (declaration) {
    case %(seq *declarations):
      foreach (List item in declarations)
        foreach (List binding in Code.declared_bindings(item))
          result.push(binding);
    case %((!or declare decl typedef) ? (bindings *bindings)):
      foreach (List binding in bindings) {
        List bound = binding;
        if (binding ~= %(op = ?target ?)) bound = target;
        match (bound) {
          case %(bind (!set ?identity (binding ? ?)) *): {
            List type = _binding_type(identity);
            result.push(%(expr $type (ident $identity)));
          }
          case %(bind ?name ?mods): {
            List row = %(
              declare $(declaration.cadr())
                (bindings (bind $name $mods))
            );
            result.push(%(expr $(row.type_from_ast()) (ident $name)));
          }
        }
      }
  }
  return result.list_free();
}

/** Returns the typed expression naming the function `name`, or an empty
    List when no function of that name is visible. This reads the symbol
    table only, so any compile-time call may use it, including one outside
    a macro expansion.
*/
List MetaContext.function_reference(String name) {
  Compiler c = active.evaluator;
  if (!c) raise %(bad-state (operation "_x2c.function.reference"));
  Type type = NULL;
  List binding = c.sym.lookup($(name), type);
  /* Lookup clears the type on misses; is_function rejects an empty Type. */
  if (!type.is_function()) return %();
  return %(expr $type (ident $binding));
}

// names and functions

/** Answers `x2c_ident`, declared in `lib/meta.x`. */
List x2c_ident(String spelling) {
  _require_expansion("x2c_ident");
  if (!spelling.is_identifier())
    $fail.meta_sdk_identifier(spelling);
  return $("x2c.ident", spelling);
}

/** Answers `x2c_binding_fresh`, declared in `lib/meta.x`. */
List x2c_binding_fresh(String role) {
  _require_expansion("x2c_binding_fresh");
  if (!role.is_identifier()) $fail.meta_sdk_binding_role(role);
  Compiler c = active.expander;
  return c.sym.introduce(c.fresh_name(role));
}

/** Answers `x2c_binding_for`, declared in `lib/meta.x`. */
List x2c_binding_for(Var key, String role) {
  _require_expansion("x2c_binding_for");
  if (!role.is_identifier()) $fail.meta_sdk_binding_role(role);
  Compiler c = active.expander;
  List binding = NULL;
  $adapter.memo(c, %(binding $key), binding)
    binding = c.sym.introduce(c.fresh_name(role));
  return binding;
}

/** Returns a fresh binding whose spelling starts with `stem`. */
Var MetaContext.fresh_binding(String stem) {
  _require_expansion("_x2c.name.unique");
  if (!stem.is_identifier())
    $fail.meta_sdk_unique_stem(stem);
  String spelling = active.expander.fresh_name(%"macro_$stem");
  return active.expander.sym.introduce(spelling);
}

/** Answers `Code.body`, declared in `lib/meta.x`. */
List Code.body(Code function) {
  if (function ~= %(function ? ? (block *body))) return body;
  return %();
}

/** Answers `Code.arguments`, declared in `lib/meta.x`. */
List Code.arguments(Code parameters) {
  if (parameters ~= %(params *items)) parameters = items;
  if (parameters ~= %((param (void) (bind () ?)))) return %();
  Array arguments = [];
  foreach (List parameter in parameters)
    if (parameter ~= %(param ? (bind ?identity *)))
      arguments.push(%(expr () (ident $identity)));
  return arguments.list_free();
}

/** Answers `Code.parameter`, declared in `lib/meta.x`. */
Code Code.parameter(Code function, String wanted) {
  List parameters = function;
  if (function ~= %(function ? (bind ? ((fnmod (params *bound)) *)) ?))
    parameters = bound;
  foreach (List parameter in parameters) {
    if (parameter ~= %(param ? (bind ?identity *)) &&
        Code.binding_spelling(identity) == wanted) {
      Type type = parameter.type_from_ast().canonicalize();
      return %(expr $type (ident $identity));
    }
  }
  $fail.meta_sdk_parameter_missing(function, wanted);
}

/** Answers `Code.name`, declared in `lib/meta.x`. */
String Code.name(Code function) {
  List identity = function;
  /* The List destination maps other value tags to nil. */
  if (function ~= %(function ? (bind ?binding ?) ?))
    identity = binding;
  return Code.binding_spelling(identity);
}



/** Answers `Code.binding_spelling`, declared in `lib/meta.x`. */
String Code.binding_spelling(Var syntax) {
  _require_expansion("Code.binding_spelling");
  if (syntax is <string>) {
    String spelling = syntax;
    if (spelling.is_identifier()) return spelling;
    $fail.meta_sdk_binding_spelling(syntax);
  }
  if (syntax is not <list> || syntax.is_nil())
    $fail.meta_sdk_binding_syntax(syntax);
  List value = syntax;
  match (value)
    case %(expr ? (!set ?content (? *))): value = content;
  match (value) {
    case %(ident (!set ?captured (*))):
      value = captured;
    case %(bind (!set ?captured (*)) ?): value = captured;
  }
  if (value ~= %((!is ?name type string))) return name;
  return _binding_spelling(value, syntax);
}

/** Returns the `Func` signature of the function syntax `syntax`. A native
    binding stores the same signature as an ordinary Func adapter.
*/
List Code.native_signature(List syntax) {
  if (syntax ~= %(function ?rtype ?declarator ?))
    return active.expander.func_signature(
      %(declare $rtype (bindings $declarator)).type_from_ast());
  return active.expander.func_signature(Code.type(syntax));
}



/** Answers the compiler-backed captured-code type query. */
Type Code.type(Code value) {
  _require_expansion("Code.type");
  match (value) {
    case %(expr ?matched_type ?): {
      Type type = matched_type;
      if (type === %(<macro-expr>))
        type = active.expander.resolve_expression(value, active.site).cadr();
      return type.canonicalize();
    }
    case %(param ? ?): return value.type_from_ast().canonicalize();
    case %((!or declare decl typedef) *):
      return value.type_from_ast().canonicalize();
  }
  List binding = NULL;
  if (Ast.try_binding(value, NULL, NULL)) binding = value;
  else
    match (value) {
      case %(ident (!set ?captured (*)) *):
        binding = captured;
      case %(bind (!set ?captured (*)) *): binding = captured;
    }
  if (binding) return _binding_type(binding).canonicalize();
  return List.type(value).canonicalize();
}

// ancestry and placement

/** Answers `x2c_enclosing`, declared in `lib/meta.x`. */
Code x2c_enclosing(Symbol what) {
  _require_expansion("x2c_enclosing");
  if (!(what in %<<declarator statement function unit>>))
    $fail.meta_sdk_enclosing_role(what);
  return active.expander.enclosing(what);
}

/** Answers `x2c_place`, declared in `lib/meta.x`. */
void x2c_place(List where, Code code) {
  _require_expansion("x2c_place");
  active.expander.place(where, code);
}

// built-in algorithm operations

/* Returns `expression` with the iterator chain `foreach` reads completed. */
List _x2c_complete_iterator(List expression) {
  _require_expansion("private foreach iterator completion");
  return active.expander.complete_iter_chain(expression);
}

// compile-time SDK syntax

static Type _binding_type(List binding) =>
  active.expander.semantic_binding_facts()[%(type $binding)];

static String _binding_spelling(List value, List syntax) {
  int identity = 0, String spelling = NULL;
  if (value ~= %(binding ?id (!is ? type string)) &&
      (!id.is_integer() || id.integer() > INT_MAX))
    $fail.meta_sdk_binding_known(value);
  if (!Ast.try_binding(value, identity, spelling))
    $fail.meta_sdk_binding_identifier(syntax);
  Var registered =
    active.expander.semantic_binding_facts()[%(known $identity)];
  /* The tag test establishes the String payload used by the comparison. */
  if (registered is not <string> || registered.string_payload() != spelling)
    $fail.meta_sdk_binding_known(value);
  return spelling;
}
