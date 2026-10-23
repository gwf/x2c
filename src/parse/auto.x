/*  auto.x -- managed declarations and local type inference */

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
  Compiler c, Symbol tag, Type base, List declarators) {
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
      while (type.car() is <symbol> &&
             type.car().symbol().is_type_qualifier()) type = type.cdr();
      Type resolved = c.sym.normalize_declared_type(type);
      if (resolved == %(void)) $fail.parse_auto_inference(c, c.token);
      if (resolved.is_array()) type = %(* @{resolved.dereference()});
      else if (resolved.is_function()) type = %(* @type);
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
