/*  defer.x -- defer regions and callable finalizers */

// defer statements

/* The automatic objects a callable defer's finalizer reads: each one's
   environment field, the bindings the finalizer declares itself, and the
   captured ones it writes. */
static typedef struct DeferCaptures {
  Compiler c;
  List declared, written;
  Map captures;
  Array records;
  int unsupported;
} DeferCaptures;

/** Writes captured addresses in the order capture selection established. */
List Ast.defer_captures(List environment, List records) {
  Array assignments = [];
  foreach (List row in records) {
    /* The capture's storage type keeps a reference parameter's own
       address; the bare binding would read through the reference. */
    List captured = $!($(row.cadr())){ $(row.car()) };
    String field = Ast.binding_spelling(row.caddr());
    assignments.push($!{ $environment.$field = (const void *)&$captured; });
  }
  return assignments.list_free();
}

/** Returns `stmts` with each `defer` statement and the statements after
    it replaced by one region; a list without `defer` returns unchanged.
*/
List Compiler.rewrite_defer_list(Compiler c, List stmts) {
  for (List suffix = stmts; suffix; suffix = suffix.cdr()) {
    List anchored = suffix.car();
    List head = Ast.without_origin(anchored);
    if (head ~= $deferred(?final_stmt)) {
      List rest = c.rewrite_defer_list(suffix.cdr());
      List finalizer = final_stmt;
      if (c.source_map) finalizer = Ast.rewrap_origin(anchored, finalizer);
      List region = c.lower_defer_region(
        %(block @rest), finalizer);
      Array before = [];
      for (List item = stmts; item != suffix; item = item.cdr())
        before.push(item.car());
      before.push(Ast.rewrap_origin(anchored, region));
      return before.list_free();
    }
  }
  return stmts;
}

/** Returns the region that runs `finalizer` when `body` leaves. Ordinary
    cleanup statements take the callable chain; lexical transfers and
    unsupported capture types keep the landing-frame path.
*/
List Compiler.lower_defer_region(Compiler c, List body, List finalizer) {
  if (c.source_map && c.origin) finalizer = %(at $(c.origin) $finalizer);
  if (_defer_needs_landing(finalizer)) return _landing_region(body, finalizer);
  return _callable_defer(c, body, finalizer);
}

/* A region that lands is a `try` the kernel writes, marked `kernel` until
   the cleanup walk lowers it. */
static List _landing_region(List body, List finalizer) =>
  %(try $body () $finalizer kernel);

static int _defer_needs_landing(List ast) {
  List node;
  $ast.walk(ast, node)
    if (node ~= %((!or return break continue goto try catchcases match) *))
      return 1;
  return 0;
}

/* The finalizer becomes a file-static thunk. Captured objects reach it
   through an environment of their addresses, filled where the region
   registers. */
static List _callable_defer(Compiler c, List body, List finalizer) {
  DeferCaptures d = {
    .c = c, .declared = %(), .written = %(),
    .captures = {}, .records = []
  };
  _collect_captures(d, finalizer);
  if (d.unsupported) {
    d.records.free();
    return _landing_region(body, finalizer);
  }
  List env_binding = NULL, env_local = NULL;
  List records = d.records.list_free();
  if (records) {
    env_binding = c.sym.introduce(c.fresh_name("defer_env"));
    env_local = c.sym.introduce(c.fresh_name("defer_data"));
    c.add_early(_defer_environment(c, env_binding, records));
  }
  List opaque = c.sym.introduce(c.fresh_name("defer_opaque"));
  List callback = c.sym.introduce(c.fresh_name("defer_cleanup"));
  String env_name = env_local ? Ast.binding_spelling(env_local) : NULL;
  List rewritten = env_name
    ? _rewrite_captures(d, finalizer, env_name) : finalizer;
  c.add_early(
    _defer_callback(c, callback, opaque, env_binding, env_local, rewritten));
  if (c.fn_name)
    c.set_fact(%(defer-ownr $callback), c.fn_name);
  return %(defer $body $env_binding $callback $records $(d.written));
}

static void _collect_captures(DeferCaptures &d, List ast) {
  if (!ast || d.unsupported) return;
  if (ast ~= %(bind ?bound *)) {
    List binding = bound, known = d.declared;
    if (!(binding in known)) d.declared = cons(binding, known);
  }
  if (ast ~= %(expr ? (ident ?bound))) {
    _capture(d, bound);
    return;
  }
  List modified = Ast.lvalue_binding(Ast.written_operand(ast));
  foreach (Var child in ast) if (child is <list>) _collect_captures(d, child);
  Var field;
  List changed = d.written;
  if (modified && d.captures.try_get(modified, field) &&
      !(modified in changed))
    d.written = cons(modified, changed);
}

static void _capture(DeferCaptures &d, List binding) {
  Compiler c = d.c;
  Map facts = c.semantic_binding_facts();
  if (!binding || binding in d.declared ||
      !(%(automatic $binding) in facts) || binding in d.captures) return;
  Var stored_type = facts[%(type $binding)];
  if (!_defer_type_hoistable(c, stored_type)) {
    d.unsupported = 1;
    return;
  }
  List field = c.sym.introduce(c.fresh_name("defer_capture"));
  d.captures[binding] = field;
  d.records.push($(binding, stored_type, field));
}

/* File-static cleanup thunks cannot name block-local or variably-sized types.
   Those types use the landing-frame lowering. */
static int _defer_type_hoistable(Compiler c, Type type) {
  if (!type) return 0;
  Type flat = type.flatten_all();
  if (<register> in flat || <dim> in flat) return 0;
  Type base = type.base_type();
  if (!base) return 0;
  Var first = base.car();
  if (first is <string>) return c.sym.get($(first)) != NULL;
  if (first == <struct> || first == <union> || first == <enum>)
    return base.len() == 2 && c.sym.get(base) != NULL;
  return 1;
}

/* Captured object references become pointer dereferences through the thunk
   environment. Expression types remain the source expression's type. */
static List _rewrite_captures(
  DeferCaptures &d, List ast, String env_name) {
  if (!ast) return ast;
  if (ast ~= %(expr ?captured_type
      (ident ?bound))) {
    List binding = bound;
    Var field_var;
    if (!d.captures.try_get(binding, field_var)) return ast;
    String field_name = Ast.binding_spelling(field_var);
    Type type = captured_type, target = type;
    if (binding in d.written &&
        !(<volatile> in type.flatten_all()))
      target = cons(<volatile>, type);
    Type pointer = cons(<*>, target);
    String reference = %"$env_name->$field_name";
    List source = %(expr (* const void) $reference);
    List cast = %(expr $pointer (cast $pointer $source));
    List dereference = %(expr $type (op * $cast));
    return %(expr $type (parens $dereference));
  }
  List child;
  $ast.rewrite_children(ast, child, _rewrite_captures(d, child, env_name));
}

/* Bind the generated type so its fields are visible to the record template.
   Field rows remain canonical syntax: separately binding a Field template
   loses its member type before the enclosing typedef is bound. */
static List _defer_environment(
  Compiler c, List env_binding, List records) {
  Array fields = [];
  foreach (List record in records)
    fields.push(
      c.rebuild_statement($!{ const void *$(record.caddr()); }).cadr());
  return c.capture_environment(env_binding, fields.list_free());
}

/* Preserve the lowered finalizer while binding the new function entry;
   the captured variant also points its local at the environment. */
static List _defer_callback(
  Compiler c, List callback, List opaque, List env_binding,
  List env_local, List rewritten) {
  List body = Code.lowered(%(seq $rewritten), NULL);
  if (env_binding) {
    Type type = $(Ast.binding_spelling(env_binding));
    return c.bind_syntax(
      $!Unit{ static void $callback(void *$opaque) {
        $type *$env_local = ($type *)$opaque;
        $body
      }
    }, <unit>, NULL);
  }
  return c.bind_syntax(
    $!Unit{ static void $callback(void *$opaque) { $body } }, <unit>, NULL);
}
