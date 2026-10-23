/*  transfers.x -- protected regions and control transfers */

/* The walk state for one function body: the open regions, the depths a
   `break` and `continue` unwind to, the depth the innermost switch opened
   at, and each label's region ancestry. */
static typedef struct Walk {
  Compiler c;
  Array regions;
  int break_stop, continue_stop, switch_stop, origin;
  Map labels;
} Walk;

/* The runtime type of a defer region's record. */
static String _record_type = "X2CCleanup";

static macro Stmt $fail.cleanup_case_region(Expr $w, Expr $site) =>
  _report_at(
    $w, $site, "case label cannot enter a protected cleanup region",
    %("open the region inside the case's own block"));

static macro Stmt $fail.cleanup_goto_missing(Expr $w, Expr $site) =>
  _report_at(
    $w, $site, "goto target label is not defined in this function",
    NULL);

static macro Stmt $fail.cleanup_goto_region(Expr $w, Expr $site) =>
  _report_at(
    $w, $site, "goto cannot enter or cross a protected cleanup region",
    %("jump only within the same region or outward"));

/* Expressions may nest one level per operator. Visit blocks without
   recursing through the expression spine; each keeps its cleanup owner. */
static Array _expression_blocks(List expression) {
  Array blocks = [];
  List node;
  $ast.walk(expression, node) if (node.car() == <block>) {
    blocks.push(node);
    continue;
  }
  return blocks;
}

/* Rebuild only the ancestors of changed blocks, from the leaves upward.
   Keys are node addresses: structural hashing would revisit the same spine. */
module List _rewrite_expression(List expression, Func rewrite) {
  Array blocks = $auto(_expression_blocks(expression));
  Map changed = $auto({});
  // The worklist visits siblings last first; initializers run in source order.
  while (blocks.len()) {
    List block = blocks.take_last();
    List replacement = rewrite(block);
    if (replacement != block) changed[(void *)block] = replacement;
  }
  return changed.len() ? Ast.replace_nodes(expression, changed) : expression;
}

// function cleanup

/** Lowers the cleanup regions and transfers of the completed top-level
    `node`; other nodes pass through. Unit normalization calls this at
    function completion. Expressions cannot contain an unlifted function, so
    no second unit-tree traversal is needed.
*/
List Compiler.lower_cleanup(Compiler c, List node) {
  match (node) {
    case %(function *): return _lower_function(c, node);
    case %(at ?origin ?inner):
      return %(at $origin ${c.lower_cleanup(inner)});
  }
  return node;
}

/* Each function walks on its own: no loop, switch, or region spans a
   function boundary, including a lambda body lifted into a sibling. A
   `return` converts to the function's declared result, including one that
   a rule's replacement for a `try` writes. */
static List _lower_function(Compiler c, List node) {
  match (node)
    case %(function ?type ?bindings ?body): {
      List declaration = %(declare $type (bindings $bindings));
      $let(c.return_type, Ast.declared_return(declaration))
        return _lowered_function(c, type, bindings, body);
    }
  return node;
}

static List _lowered_function(
  Compiler c, List type, List bindings, List body) {
  Walk w = {.c = c, .regions = [], .labels = {}};
  Map runtime = {};
  body = _static_regions(c, body, runtime);
  _collect_labels(w, body, NULL);
  Preserve p = {
    .c = c, .names = {}, .holders = {}, .pointers = {}, .escaped = {}
  };
  _collect_writes(p, body);
  List rewritten = _rewrite(w, body);
  if (p.names.len() || p.escaped.len()) {
    p.expression_landings = _expression_holds_landing(body);
    rewritten = _preserve_locals(p, rewritten);
    bindings = _preserve_locals(p, bindings);
    rewritten = _escape_parameters(p, rewritten, bindings);
  }
  w.regions.free();
  return %(function $type $bindings $rewritten);
}

// region walk

/* Collect each label's region ancestry before any `goto` is rewritten, so a
   jump backward to a label reads the same ancestry as a jump forward. The
   ancestry is the chain of region nodes enclosing the label, and the rewrite
   compares against the same nodes. */
static void _collect_labels(Walk &w, Var value, List path) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    case %(expr *): _collect_blocks(w, node, path);
    case %(label ?name *rest): _collect_label(w, name, rest, path);
    case %(landing ? ?rows): _collect_rows(w, rows, path);
    case %(defer ?body *): _collect_labels(w, body, cons(body, path));
    case %(localinit ?guard ?body):
      _collect_local(w, node, guard, body, path);
    case %(staticinit ? ?initial):
      _collect_labels(w, initial, cons(node, path));
    default: _collect_children(w, node, path);
  }
}

static void _collect_blocks(Walk &w, List node, List path) {
  Array blocks = $auto(_expression_blocks(node));
  foreach (List block in blocks) _collect_labels(w, block, path);
}

static void _collect_label(Walk &w, Var name, List rest, List path) {
  String spelling = _label_spelling(name);
  if (spelling) w.labels[spelling] = path;
  _collect_children(w, rest, path);
}

/* Each region a landing opens has its own identity, such as a `try` body
   and each catch arm, while its outer parts keep the enclosing path. */
static void _collect_rows(Walk &w, List rows, List path) {
  foreach (List row in rows)
    match (row) {
      case %(outer ? ?node): _collect_labels(w, node, path);
      case %(region ? ?node): _collect_labels(w, node, cons(node, path));
    }
}

static void _collect_local(
  Walk &w, List node, Var guard, Var body, List path) {
  _collect_labels(w, guard, path);
  _collect_labels(w, body, cons(node, path));
}

static void _collect_children(Walk &w, List node, List path) {
  foreach (Var child in node) _collect_labels(w, child, path);
}

/* A label reads as a binding, as a wrapped expression, or as the bare name
   a macro wrote. */
static String _label_spelling(Var label) {
  if (label is <string>) return label;
  if (label is not <list>) return NULL;
  List node = label;
  match (node) {
    case $source_identifier_content(%(?binding)):
      return Ast.binding_spelling(binding);
    case %(expr ? ?inner): return _label_spelling(inner);
    case $source_content_pattern($grouped, %(?inner)):
      return _label_spelling(inner);
    case %(?(String name)): return name;
  }
  return Ast.binding_spelling(node);
}

/* Only a statement expression lets an expression hold transfers or
   regions, and expressions may nest arbitrarily. Position wrappers supply
   report origins. Bound returns carry one expression; the source template's
   declared-type slot is not a matching source form. */
static Var _rewrite(Walk &w, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  match (node) {
    case %(expr *): return _rewrite_blocks(w, node);
    case %(at ?(int origin) ?inner): return _lower_at(w, origin, inner);
    case %(defer ?body ?env ?callback ?records ?):
      return _lower_defer(w, body, env, callback, records);
    case %(landing ?code ?rows): return _lower_landing(w, code, rows);
    case %(localinit ?guard ?body):
      return _rewrite_localinit(w, node, guard, body);
    case %(staticinit ?record ?initial):
      return _rewrite_staticinit(w, node, record, initial);
    case $source_return_content(%()): return _transfer(w, 0, node);
    case $source_return_content(%((!set ?expression (expr ? ?)))):
      return _lower_return(w, node, expression);
    case %(break): return _transfer(w, w.break_stop, node);
    case %(continue): return _transfer(w, w.continue_stop, node);
    case %(goto ?label): return _transfer(w, _goto_stop(w, label), node);
    case ${$while_loop(?condition, ?body)}:
      return _rewrite_while(w, condition, body);
    case ${$do_loop(?body, ?condition)}:
      return _rewrite_do(w, body, condition);
    case ${$for_loop(?initial, ?condition, ?increment, ?body)}:
      return _rewrite_for(w, initial, condition, increment, body);
    case ${$switched(?subject, ?body)}:
      return _rewrite_switch(w, subject, body);
    case %((!or case default) *): return _case_label(w, node);
    case %(function *): return _lower_function(w.c, node);
    default: return _rewrite_children(w, node);
  }
}

static List _rewrite_blocks(Walk &w, List node) =>
  _rewrite_expression(node, %!(List block) using &w => _rewrite(w, block));

static List _rewrite_children(Walk &w, List node) {
  Var child;
  $ast.rewrite_children(node, child, _rewrite(w, child));
}

/* Lowers `inner` with `origin` as the source position of its reports. */
static Var _lower_at(Walk &w, int origin, Var inner) {
  int previous = w.origin;
  w.origin = origin;
  Var lowered = _rewrite(w, inner);
  w.origin = previous;
  return %(at $origin $lowered);
}

/* Lowers a return of `expression`, after any statement expression in it:
   only a region that runs something can change what the expression read,
   so a static-local region alone leaves the return as it is. */
static List _lower_return(Walk &w, List node, List expression) {
  List value = _rewrite(w, expression);
  if (value != expression) node = source_return_content(%($value));
  List cleanup = _unwind(w, 0);
  return cleanup ? _return_value(w, value, cleanup) : node;
}

/* Save the returned value before cleanup runs, since cleanup may change the
   state the expression read. */
static List _return_value(Walk &w, List expression, List cleanup) {
  List binding = _region_binding(w.c, "return_value");
  Type type = w.c.return_type;
  List declaration =
    w.c.rebuild_statement($!{ $type $binding = $expression; }).cadr();
  List returned = source_return_content(%((expr $type (ident $binding))));
  List statement = source_block_content(%(@cleanup $returned));
  return source_block_content(%($declaration $statement));
}

/* A function-static initializer remains in ancestry for label checks,
   although no exit runs its record. */
static List _rewrite_localinit(
  Walk &w, List node, List guard, List body) =>
  %(localinit ${_rewrite(w, guard)} ${_inside(w, NULL, node, body)});

static List _rewrite_staticinit(
  Walk &w, List node, List record, List initial) =>
  %(staticinit $record
    ${_inside(w, _defer_cleanup(w.c, record), node, initial)});

static List _rewrite_while(Walk &w, List condition, List body) =>
  %(while ${_rewrite(w, condition)} ${_bounded(w, body, 1)});

static List _rewrite_do(Walk &w, List body, List condition) =>
  %(do ${_bounded(w, body, 1)} ${_rewrite(w, condition)});

static List _rewrite_for(
  Walk &w, List initial, List condition, List increment, List body) =>
  %(for ${_rewrite(w, initial)} ${_rewrite(w, condition)}
        ${_rewrite(w, increment)} ${_bounded(w, body, 1)});

static List _rewrite_switch(Walk &w, List subject, List body) {
  int saved = w.switch_stop;
  w.switch_stop = (int) w.regions.len();
  List result = %(switch ${_rewrite(w, subject)} ${_bounded(w, body, 0)});
  w.switch_stop = saved;
  return result;
}

/* A case label is a jump target of its switch, so it may not sit inside a
   region with exits opened since the switch began; a `goto` into one is
   rejected the same way. A static initializer's region has no exits, and
   the emitter reports a switch that bypasses it. */
static List _case_label(Walk &w, List label) {
  for (int i = w.switch_stop; i < (int) w.regions.len(); i++)
    if (w.regions[i].list().car()) {
      $fail.cleanup_case_region(w, w.origin);
      break;
    }
  return _rewrite_children(w, label);
}

/* Rewrite a construct's body with the transfer barriers it establishes. A
   loop bounds both `break` and `continue`; a switch bounds only `break`,
   because a `continue` inside it still targets the enclosing loop. */
static Var _bounded(Walk &w, Var body, int is_loop) {
  int saved_break = w.break_stop, saved_continue = w.continue_stop;
  w.break_stop = (int) w.regions.len();
  if (is_loop) w.continue_stop = (int) w.regions.len();
  Var result = _rewrite(w, body);
  w.break_stop = saved_break;
  w.continue_stop = saved_continue;
  return result;
}

/* Rewrite a region's body and its handlers with the region open. */
static Var _inside(Walk &w, List cleanup, List marker, Var body) {
  w.regions.push(%(${_statements(cleanup)} $marker));
  Var result = _rewrite(w, body);
  w.regions.take_last();
  return result;
}

static List _statements(List code) {
  match (code) case %(code-value ? (seq *statements) ?): return statements;
  return code;
}

/* Wrap a transfer in the cleanup it runs first. A transfer that leaves no
   region keeps its own shape. */
static List _transfer(Walk &w, int stop, List statement) {
  List cleanup = _unwind(w, stop);
  return cleanup ? source_block_content(%(@cleanup $statement)) : statement;
}

/* The statements that leave every region down to `stop`, innermost first.
   Each region runs its own statements before the next one out, so an inner
   frame leaves before an outer defer runs. */
static List _unwind(Walk &w, int stop) {
  Array statements = [];
  for (int i = (int) w.regions.len() - 1; i >= stop; i--)
    foreach (List statement in w.regions[i].list().car().list())
      statements.push(statement);
  return statements.list_free();
}

/* Reject a jump that would enter a region it did not open, and return the
   depth the jump unwinds to. */
static int _goto_stop(Walk &w, Var label) {
  String name = _label_spelling(label);
  Var stored;
  if (!name || !w.labels.try_get(name, stored)) {
    $fail.cleanup_goto_missing(w, w.origin);
    return (int) w.regions.len();
  }
  List target = stored, source = _region_path(w);
  int source_depth = source.len(), target_depth = target.len();
  List suffix = source;
  for (int i = source_depth; i > target_depth && suffix; i--)
    suffix = suffix.cdr();
  if (target_depth > source_depth || suffix !== target) {
    $fail.cleanup_goto_region(w, w.origin);
    return (int) w.regions.len();
  }
  return target_depth;
}

/* The open regions, innermost first. A label's ancestry is this list, and a
   jump may only leave a suffix of it. */
static List _region_path(Walk &w) {
  List path = %();
  foreach (List region in w.regions) path = cons(region.cadr(), path);
  return path;
}

/* Report at `origin`, and leave the compiler's origin as it was for whatever
   reports next. */
static void _report_at(Walk &w, int origin, String message, List note) {
  $let(w.c.origin, origin)
    w.c.report_error(<emit>, message, NULL, note);
}

/* Introduce a name this pass owns. The emitted declaration spells this
   binding, so the record a region pushes and the record its exits leave are
   one name by construction. */
module List _region_binding(Compiler c, String role) =>
  c.sym.introduce(c.fresh_name(role));

static List _address_of(String spelling, List binding) {
  Type type = %(($spelling));
  return %(expr ${type.reference()} (op & (expr $type (ident $binding))));
}

/* landings

   A construct whose parts control re-enters through `siglongjmp` takes
   the form `(landing CODE ROWS)`. The walk applies its rows in order, and
   each row's TOKEN, a binder in CODE and in the rows after it, is replaced
   by what the row lowered:

   - `(new-name TOKEN ROLE)` introduces a fresh binding for ROLE.
   - `(outer TOKEN NODE)` lowers NODE in the enclosing regions.
   - `(exits TOKEN CODE)` binds CODE as the exits of the regions after it.
     CODE holds lowered parts only, so binding lowers nothing more.
   - `(region TOKEN NODE)` lowers NODE inside a region that runs those exits
     on every transfer out of it, and that no `goto` may enter.

   CODE then binds in place of the construct. The locals that the nodes of
   `outer` and `region` rows write stay valid when control lands. */

static List _lower_landing(Walk &w, Var code, List rows) {
  Compiler c = w.c;
  Map parts = $auto({});
  List exits = NULL;
  foreach (List row in rows)
    match (row) {
      case %(new-name ?token ?(String role)):
        parts[token] = _region_binding(c, role);
      case %(outer ?token ?node):
        parts[token] = Code.lowered(%(seq ${_rewrite(w, node)}), NULL);
      case %(exits ?token ?statements):
        parts[token] = exits =
          Code.lowered(_bind_parts(c, statements, parts), NULL);
      case %(region ?token ?node): parts[token] = _region(w, exits, node);
    }
  return _bind_parts(c, code, parts);
}

/* Lowers the body inside the scope that `cleanup` leaves. */
static List _region(Walk &w, List cleanup, List body) =>
  Code.lowered(_inside(w, cleanup, body, body), NULL);

/* Binds `code` with each token `parts` maps replaced. A template's
   definition holds none, so only the values it applies are searched. */
static List _bind_parts(Compiler c, Var code, Map parts) {
  match (code) case %("x2c.template" ?definition ?values): {
    Var replaced = _replaced(values, parts);
    if (replaced != values)
      code = %("x2c.template" $definition $replaced);
    return c.bind_syntax(code, <block>, c.return_type);
  }
  return c.bind_syntax(_replaced(code, parts), <block>, c.return_type);
}

/* `value` with each token `parts` maps replaced. A List without one is
   returned as it is, so only the cells along a replaced path are new. */
static Var _replaced(Var value, Map parts) {
  Var part;
  if (value.is_binder() && parts.try_get(value, part)) return part;
  if (value is not <list> || value.is_nil()) return value;
  List list = value;
  Var head = _replaced(list.car(), parts), tail = _replaced(list.cdr(), parts);
  return head == list.car() && tail == list.cdr() ? value : cons(head, tail);
}

/* defer regions

   Registration and its captured addresses share the body's region scope. */

/* Lowers a defer: its record is pushed before the body and left on each
   of the body's exits. */
static List _lower_defer(
  Walk &w, List body, List env, List callback, List records) {
  Compiler c = w.c;
  c.needs_exception = 1;
  List record = _region_binding(c, "defer_record");
  List cleanup = _defer_cleanup(c, record);
  return c.bind_syntax(
    $!{ {
      ${_defer_record(record, callback, env, records)}
      x2c_cleanup_push(&$record);
      ${_region(w, cleanup, body)}
      $cleanup
    }
  }, <block>, c.return_type);
}

/* The runtime unlinks this record and calls its thunk. */
static List _defer_cleanup(Compiler c, List record) {
  List call = c.bind_syntax(
    $!{ x2c_cleanup_leave(${_address_of(_record_type, record)}); },
    <block>, c.return_type);
  return Code.lowered(%(seq $call), NULL);
}

/* Selects the record shape; captured records keep the environment beside
   the record in the region's scope. */
static List _defer_record(
  List record, List callback, List environment, List records) {
  if (!environment)
    return $!{ X2CCleanup $record = {.fn = $callback, .env = 0}; };
  Type type = %(${Ast.binding_spelling(environment)});
  return $!{
    $type environment = {0};
    @Ast.defer_captures(environment, $records)
    X2CCleanup $record = {.fn = $callback, .env = &environment};
  };
}
