/*  placement.x -- ancestry and deferred code placement

    Copyright (c) 2025 Gary William Flake.
*/

/* The code placed at the entry of the function whose row is at `depth`,
   bound in its parameter scope once its body is complete. */
module List _entry_code(Compiler c, int depth) {
  Array items = [];
  foreach (List row in _take_placements(c, depth))
    _push_items(items, c.bind_syntax(row[3], <block>, c.return_type));
  return items.list_free();
}

// placement and ancestry

/** Enters `row` as the innermost syntax `Compiler.enclosing` answers. Its
    owner leaves it with `Block.pop`, or with `Compiler.leave_item` for a
    block item. */
void Compiler.enter(Compiler c, Ancestor row) {
  c.ancestors.push(&row);
}

/** Returns the innermost `what` around the parser, or around the function
    body the transform lowers, as captured code, or NULL when there is none:
    the declarator whose initializer is being parsed directly in the current
    block item, as its one-declarator declaration; the block item, or the
    one the transform lowers, as its origin anchor; the function, as a
    definition whose body is still the empty `(seq)`; or the unit, as a
    `String` expression of its path. */
List Compiler.enclosing(Compiler c, Symbol what) {
  if (what == <unit>) {
    String path = c.filename ? c.display_path(c.filename) : "<stdin>";
    return $!String{ $path };
  }
  Ancestor *rows = c.ancestors.bytes;
  for (int i = (int) c.ancestors.len() - 1; i >= 0; i--) {
    Ancestor row = rows[i];
    if (row.what == what) return _ancestor_code(c, row);
    if (row.lowering && what == <statement>) return %(at ${c.origin} (seq));
    if (what == <declarator> || row.what == <function>) return NULL;
  }
  return NULL;
}

static List _ancestor_code(Compiler c, Ancestor row) {
  if (row.what == <declarator>)
    return %(declare ${row.base} (bindings ${row.node}));
  if (row.what == <function>)
    match (row.node) case %(declare ?type (bindings ?declarator)):
      return %(function $type $declarator (seq));
  int origin = row.origin ? row.origin : c.record_origin(row.token);
  return %(at $origin (seq));
}


/** Enters the function definition `declaration`, whose body the
    transform lowers next, so a rule lowering that body places code at its
    entry. Returns the row's depth for `Compiler.leave_function`. */
int Compiler.enter_function(Compiler c, List declaration, int callback) {
  int depth = c.ancestors.len();
  Ancestor row = {
    .what = <function>, .node = declaration, .lowering = 1,
    .callback = callback};
  c.enter(row);
  return depth;
}

/** Returns the code placed at the entry of the function row at `depth`
    since it was entered or last asked, in placement order, or NULL. The
    code binds in a scope of its own with the function's result type; its
    caller lowers it while the row is still entered, so a placement that
    lowering makes lands at the entry too. */
List Compiler.function_entry(Compiler c, int depth) {
  if (!c.placements.len()) return NULL;
  List declaration = ((Ancestor *) c.ancestors.bytes)[depth].node;
  c.sym.push_new_scope();
  List entry;
  $let(c.return_type, Ast.declared_return(declaration))
    entry = _entry_code(c, depth);
  c.sym.pop_scope();
  return entry;
}

/** Leaves the function row at `depth` that `Compiler.enter_function`
    began. */
void Compiler.exit_function(Compiler c, int depth) {
  c.ancestors.truncate(depth);
}

/** Records `code` for the entry of the innermost function definition,
    after its parameters bind and before its first statement. While parsing,
    a lambda body is inside the definition that holds it; while lowering, a
    lambda body is the body of its own lifted function, and a finalizer the
    kernel wrote as a callback has no entry a program can place at. */
void Compiler.place_entry(Compiler c, Var code) {
  Ancestor *rows = c.ancestors.bytes;
  int depth = (int) c.ancestors.len() - 1;
  while (depth >= 0 && rows[depth].what != <function>) depth--;
  if (depth < 0) $fail.parse_placement_function(c, c.token);
  if (rows[depth].callback) $fail.parse_placement_finalizer(c, NULL);
  c.placements.push(%($depth () () $code));
}

/** Records `code` to follow the innermost block item, or the initialized
    declarator whose initializer is being parsed directly in it. The
    expansion that placed it gives it its result when it finishes. */
void Compiler.place_after(Compiler c, Var code) {
  Ancestor *rows = c.ancestors.bytes;
  int depth = (int) c.ancestors.len() - 1;
  List binding = NULL;
  if (depth >= 0 && rows[depth].what == <declarator>)
    binding = rows[depth--].node.cadr();
  if (depth < 0 || rows[depth].what != <statement>)
    $fail.parse_placement_item(c, c.token);
  c.placements.push(%($depth $binding () $code));
}

/** Gives the placements made since `first` the `result` of the expansion
    that made them. */
void Compiler.close_placements(Compiler c, int first, List result) {
  for (int i = first; i < (int) c.placements.len(); i++) {
    (int depth, List binding, List placed, Var code) = c.placements[i].list();
    if (!placed) c.placements[i] = %($depth $binding $result $code);
  }
}

/** Leaves the block item `enter` began and returns the code placed after
    it, bound in its block, or NULL. A declarator in the item that placed
    code is incomplete unless its block declaration took that code. */
List Compiler.leave_item(Compiler c) {
  int depth = (int) c.ancestors.len() - 1;
  Ancestor row = ((Ancestor *) c.ancestors.bytes)[depth];
  c.ancestors.pop();
  List placed = _take_placements(c, depth);
  if (!placed) return NULL;
  Array items = [];
  foreach (List placement in placed) {
    (Var anchor, List binding, Var result, Var code) = placement;
    (void) anchor, (void) result;
    if (binding)
      $let(c.origin, row.origin ? row.origin : c.origin)
        $fail.parse_init_incomplete(c, row.token);
    _push_items(items, c.bind_syntax(code, <block>, c.return_type));
  }
  return items.list_free();
}

/* Removes the placements anchored at the ancestor row `depth` and returns
   them in placement order. */
static List _take_placements(Compiler c, int depth) {
  if (!c.placements.len()) return NULL;
  Array taken = [];
  int kept = 0;
  for (int i = 0; i < (int) c.placements.len(); i++) {
    List row = c.placements[i];
    if (row.car().int() == depth) taken.push(row);
    else c.placements[kept++] = row;
  }
  c.placements.resize(kept);
  return taken.list_free();
}

/** Lowers block declarations whose declarators placed code after
    themselves, or that an after-initialization rewrite follows, to
    declarations followed by that code in source order, preserving their
    installed bindings and the enclosing lifetime.
*/
List Compiler.finish_initializers(
  Compiler c, List declaration, Token origin) {
  if (c.macro_holes ||
      (!c.placements.len() && !c.has_rewrites(<decl>, <init>) &&
       !_auto_storage(declaration)))
    return declaration;
  Array output = [];
  _append_managed(c, declaration, output, origin);
  return %(seq @{output.list_free()});
}

static void _append_managed(
  Compiler c, List declaration, Array output, Token origin) {
  match (declaration) {
    case %(seq *rows): {
      foreach (List row in rows)
        _append_managed(c, row, output, origin);
      return;
    }
    case %(declare ?base (bindings *declarators)): {
      _append_managed_rows(c, base, declarators, output, origin);
      return;
    }
  }
  output.push(declaration);
}

/* A declarator followed by code ends the declaration of the ordinary
   declarators before it, is declared alone, and is followed by its code. */
static void _append_managed_rows(
  Compiler c, List base, List declarators, Array output, Token origin) {
  Array ordinary = auto [];
  List source_base = base;
  if (<auto> in base) base = base.filter(%!(item) => item != <auto>);
  size_t remaining = declarators.len();
  foreach (List declarator in declarators) {
    remaining--;
    List after = _after_declarator(c, source_base, declarator, origin);
    if (!after) {
      ordinary.push(declarator);
      continue;
    }
    if ((remaining || ordinary.len()) && base.type().base_type().body())
      base = _share_declaration_type(c, base, output);
    if (ordinary.len()) {
      output.push(%(declare $base (bindings @{ordinary})));
      ordinary.clear();
    }
    output.push(%(declare $base (bindings $declarator)));
    _push_items(output, after);
  }
  if (ordinary.len())
    output.push(%(declare $base (bindings @{ordinary})));
}

/* The code placed after an initialized `declarator`, which then takes the
   placing expansion's result as its initializer, or else the items an
   after-initialization rewrite adds, or NULL. */
static List _after_declarator(
  Compiler c, List base, List &declarator, Token origin) {
  match (declarator)
    case %(op = (bind ?name ?mods) ?value): {
      List result = NULL;
      List placed = _take_placed(c, name, value, result, origin);
      if (placed) {
        declarator = %(op = (bind $name $mods) $result);
        return placed;
      }
      List ordinary = <auto> in base
        ? base.filter(%!(item) => item != <auto>) : base;
      List rewritten = c.rewrite(
        <decl>, <init>, %(declare $ordinary (bindings $declarator)), <block>,
        c.return_type, origin);
      if (<auto> in base) {
        Type type = %(declare $base (bindings (bind $name $mods))).type_from_ast();
        List release = c.resolve_protocol_member(type, "cleanup")
          ? c.bind_syntax($!{ defer $name.cleanup(); }, <block>, c.return_type)
          : NULL;
        if (release) return rewritten ? %(seq $release $rewritten) : release;
      }
      return rewritten;
    }
  return NULL;
}

/* Takes the placements anchored at `binding` and returns their code bound
   in the block, or NULL. Each placing expansion's result must be the
   complete initializer `value`, and becomes the declarator's initializer. */
static List _take_placed(
  Compiler c, List binding, List value, List &result, Token origin) {
  if (!c.placements.len()) return NULL;
  Array kept = [], code = [];
  foreach (List row in c.placements) {
    (Var depth, List anchor, List placed, Var item) = row;
    (void) depth;
    if (anchor !== binding) {
      kept.push(row);
      continue;
    }
    if (!_complete(value, placed))
      $fail.parse_init_incomplete(c, origin);
    if (item in code) $fail.parse_placement_repeated(c, origin);
    result = placed;
    code.push(item);
  }
  if (!code.len()) return NULL;
  c.placements = kept;
  Array items = [];
  foreach (Var item in code)
    _push_items(items, c.bind_syntax(item, <block>, c.return_type));
  return %(seq @{items.list_free()});
}

/* Parentheses and typed expression shells preserve the position of a
   complete initializer; operators do not. */
static int _complete(List syntax, List result) {
  if (syntax === result) return 1;
  match (syntax) {
    case %(expr ? ?inner): return _complete(inner, result);
    case $source_content_pattern($grouped, %(?inner)):
      return _complete(inner, result);
  }
  return 0;
}

/* A split declaration still defines its shared type once. An ordinary local
   typedef retains qualified aggregate and enum identity without copying the
   definition into each emitted declaration. Variable storage stays outside. */
static Type _share_declaration_type(
  Compiler c, Type base, Array output) {
  List name = c.sym.introduce(c.fresh_name("declaration_type"));
  Type value = base.declared();
  List alias =
    c.bind_syntax($!{ typedef $value $name; }, <block>, c.return_type);
  _push_items(output, alias);
  Array storage = [];
  foreach (Var item in base)
    if (item is <symbol> && item.symbol().is_storage_class())
      storage.push(item);
  return %(@{storage.list_free()} $name);
}
