/*  auto.x -- managed declarations, local type inference, and the forms
    `auto` begins

    Copyright (c) 2026 Gary William Flake.
*/

// recognition

/** Reports what the `auto` at the cursor wraps as an allocation region:
    `<statement>` for a statement, a block, `foreach`, or `with`, each with
    or without a destination; `<function>` at `position` `<unit>` for
    file-scope declaration syntax whose body follows, which the ordinary
    function parser then requires; or 0 for a managed declaration or any
    other use of the word. This query does not consume tokens.
*/
Symbol Compiler.auto_region_form(Compiler c, Symbol position) {
  if (c.peek(0) != <auto>) return 0;
  Token next = Token.skip_trivia(c.token + 1);
  if (next.type == <(>) {
    Token after = Token.skip_trivia(next.after_group());
    return position == <unit> && _function_follows(c, after)
         ? <function> : <statement>;
  }
  if (next.text == "foreach" || next.text == "with" ||
      next.type in _region_statements)
    return <statement>;
  return position == <unit> && _function_follows(c, next) ? <function> : 0;
}

static const SymbolSet _region_statements =
  %<<"{" "%{" if while for do switch match try return raise defer break
     continue goto>>;

/* Whether `token` begins a declaration that stays at file scope. */
static int _function_follows(Compiler c, Token token) {
  Token start = c.token;
  defer c.token = start;
  c.token = token;
  return c.test_declaration() && _declaration_stays(c);
}

module int _auto_storage(List declaration) {
  match (declaration) {
    case %(declare ?(List base) *): return <auto> in base;
    case %(seq *rows): {
      foreach (List row, rows) if (_auto_storage(row)) return 1;
    }
  }
  return 0;
}

/* Complete inference before ordinary declaration conversion. An explicit
   auto type already has its installed binding and needs only placement and
   initializer checks. */
module List _auto_declaration(
  Compiler c, Symbol tag, Type base, List declarators, List &before) {
  if (tag != <declare> || !c.enclosing(<function>) ||
      base.is_static() || base.is_extern() || base.is_threaded())
    $fail.parse_auto_storage(c, c.token);
  int inferred = !base.base_type();
  if (inferred && declarators.len() != 1)
    $fail.parse_auto_inference(c, c.token);
  foreach (List declarator, declarators) {
    List binding = NULL, mods = NULL, value = NULL;
    match (declarator) {
      case %(op = (bind ?name ?modifiers) ?initial):
        binding = name, mods = modifiers, value = initial;
      default: $fail.parse_auto_storage(c, c.token);
    }
    if (%(managed $binding) in c.semantic_binding_facts())
      $fail.parse_auto_combined(c, c.token);
    if (inferred) {
      Type type = value.cadr();
      if (mods || !type || type == %(void) || type == %(<macro-expr>))
        $fail.parse_auto_inference(c, c.token);
      Type resolved = c.sym.normalize_declared_type(type);
      Type shape = resolved;
      while (shape.car() is <symbol> &&
             shape.car().symbol().is_type_qualifier()) shape = shape.cdr();
      if (shape == %(void)) $fail.parse_auto_inference(c, c.token);
      if (shape.is_array()) type = %(* @{resolved.dereference()});
      else if (shape.is_function()) type = %(* @type);
      else {
        while (type.car() is <symbol> &&
               type.car().symbol().is_type_qualifier()) type = type.cdr();
        if (c.sym.normalize_declared_type(type) != shape)
          type = %(unqual @type);
      }
      before = _auto_native_type(c, type, value);
      base = %(@base @type);
    }
    Type type = %(declare $base (bindings (bind $binding $mods)))
      .type_from_ast().declared();
    if (type.is_function())
      $fail.parse_auto_storage(c, c.token);
    c.sym.bind_identity(NULL, binding,
      %(declare ${base.declared()} (bindings (bind $binding $mods))));
    c.set_fact(%(managed $binding), 1);
  }
  return base;
}

/* A previously defined anonymous type needs a native name. typeof does
   not evaluate its operand; the existing native-alias map keeps the tag's
   semantic identity while emission uses this private typedef. */
static List _auto_native_type(Compiler c, Type type, List value) {
  Type base = type.base_type();
  match (base) case %((!or struct union enum) (gensym *)): {
    while (type.is_pointer() || type.is_array()) {
      type = type.dereference();
      value = %(expr $type (op * $value));
    }
    List alias = c.sym.introduce(c.fresh_name("inferred_type"));
    c.set_fact(%(ntype $alias), base);
    value = %(expr $type
      (commas (expr (int) (literal (int) "0")) $value));
    return %(typedef ("__typeof__" (parens $value))
      (bindings (bind $alias ())));
  }
  return NULL;
}
