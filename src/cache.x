/*  cache.x -- cached literal slots and deferred file-static initializers

    Copyright (c) 2025 Gary William Flake.

    This module materializes a unit's cached literals between lowering and C
    emission: it declares their static slots, initializes them in the unit's
    initialization phases, and moves file-static initializers C cannot
    evaluate into generated helpers. Immutable values share generated
    storage; mutable collections are copied at use sites, so caching does not
    change identity.

    `Compiler.cache` in compiler.x decides cache-key equality and assigns the
    `(cache id)` nodes whose ids index `Compiler.id_keys`; this module trusts
    that mapping. Header and source regions may materialize the same
    immutable value in separate static slots; `String` and `List`
    canonicalization preserves value identity across them.
*/
#pragma once
#include "compiler.x"
#pragma private
$(import "../src/ast-rewrite.xmacro")
#include "type.x"
#include "var.x"
#include "string.x"
#include "transform.x"
#include "cleanup.x"
#include "expressions.x"
#include "generate.x"
#include "logger.x"
#include <stdio.h>
#include <stdint.h>
#include <assert.h>

// diagnostics

macro Stmt $report.cache.init_cycle(Expr $c, Expr $origin, Expr $notes) {
  $c.report_error(
    <cache>, "file-static x2c initializer dependency cycle",
    $origin, $notes);
}

// cache materialization

/** Materializes cached literals and deferred file-static initialization.
    `header` and `source` must be partitioned lowered AST regions from this
    compiler. Every `(cache id)` must index `c.id_keys`, and file-static
    dependency state from the full parse must be complete. `prefix`,
    `guard_name`, and `initializer_name` name the header's private slots,
    guard, and initializer. Returns `(header source bindings)`; `bindings`
    maps source cache ids to emitted slots. Appends initialization work
    to the compiler's early, middle, and late initialization phases; the
    operation is not idempotent. Header cache storage remains private to each
    C translation unit that includes it.
*/
List Compiler.setup_cache_init(
  Compiler c, List header, List source, String prefix,
  String guard_name, String initializer_name) {
  Array initializers = [];
  header = c._rewrite_statics(header, initializers);
  Array header_ids = c._cache_ids(header);
  /* A deferred header initializer is now in the source's initializer,
     so its slots belong to the source region. */
  Array scan = [];
  scan.push(source);
  foreach (Var initializer, initializers) scan.push(initializer);
  foreach (Var initializer, c.inits) scan.push(initializer);
  Array source_ids = c._cache_ids(scan.list_free());
  if (header_ids)
    header = c._header_cache(
      header, header_ids, prefix, guard_name, initializer_name);
  Map bindings = c._cache_bindings(source_ids, NULL);
  source = c._source_cache(source, source_ids, bindings, initializers);
  initializers.free();
  return %($header $source $bindings);
}

static Array Compiler._cache_ids(Compiler c, List code) {
  List seen[4096] = { 0 };
  Array ids = [];
  c._collect_ids(code, seen, ids);
  if (!ids) {
    ids.free();
    return NULL;
  }
  return ids;
}

/* Collect dependencies before their users, in first-use source order.
   Cold collection can allocate keys that interface replay never needs; only
   this reachable order chooses emitted slots, leaving semantic ids intact.
   Generated ASTs are canonical DAGs rather than trees, so the direct-mapped
   identity memo avoids repeatedly walking shared subgraphs. A collision only
   replaces one memo entry and may cause harmless extra work. */
static void Compiler._collect_ids(
  Compiler c, Var value, List *seen, Array ids) {
  Array pending = $auto([%($value)]), marked = $auto([]);
  marked.resize(c.id_keys.len());
  while (pending) {
    Var frame = pending[-1];
    if (frame.is_integer()) {
      ids.push(pending.take_last());
      continue;
    }
    List cursor = frame;
    if (!cursor) {
      pending.take_last();
      continue;
    }
    pending[-1] = cursor.cdr();
    Var current = cursor.car();
    if (current is not <list>) continue;
    List node = current;
    unsigned slot = ((uintptr_t) node >> 4) & 4095;
    if (seen[slot] == node) continue;
    seen[slot] = node;
    match (node)
      case %(cache ?captured_id): {
        int id = captured_id;
        if (!marked[id].is_null()) continue;
        marked[id] = 1;
        pending.push(id);
        pending.push(%(${c.id_keys[id]}));
        continue;
      }
    pending.push(node);
  }
}

/* file-static rewrites

   C does not allow a non-constant static initializer, and after lowering
   most file-static initializers are calls. Each such binding keeps its
   declaration and moves its assignment into a generated helper. */

/* The function `type name(void)` running `body`. */
List _initializer_function(Compiler c, Type type, List name, List body) =>
  c.rebuild_unit_function($!Unit{ $type $name(void) { $body... } });

/* Returns when `guard` is set and sets it otherwise. */
List _run_once(Compiler c, List guard) {
  List flag = $!int{ $guard };
  return c.rebuild_statement($!{ if ($flag) return; $flag = 1; }).cdr();
}

/* The statement calling the `void (void)` function `entry`. */
List _entry_call(String entry) =>
  %((stmnt (expr (void) (call $entry (args)))));

/* The statement calling the `void (void)` function `helper` names. */
static List Compiler._helper_call(Compiler c, List helper) {
  List callee = %(expr ((func ((void))) void) (ident $helper));
  return c.rebuild_statement($!{ $callee(); }).cadr();
}

/* Apply file-scope initializer rewrites across one generated region. Both
   regions share one initializer list, so a header definition deferred into
   the source's initializer is ordered against the file statics it reads. */
static List Compiler._rewrite_statics(
  Compiler c, List code, Array initializers) {
  Array output = [], List arms = NULL;
  foreach (List item, code) {
    int first = initializers.len();
    match (item) {
      case %(!set ?declaration (declare *)):
        item = c._rewrite_static(declaration, initializers);
      case %(preproc ?content): arms = preproc_track_arms(arms, content);
    }
    output.push(item);
    for (int i = first; i < initializers.len(); i++) {
      (List binding, List assignment) = initializers[i];
      List helper = c.sym.introduce(c.fresh_name("static_initialize"));
      initializers[i] = %($binding $assignment $helper $arms);
      List function =
        _initializer_function(c, %(static void), helper, %($assignment));
      output.push(%(sourceinit $function));
    }
  }
  return output.list_free();
}

/* Lowering turns most non-const file-static initializers into calls, so they
   run in the initializer phase. A public object or a const object defers only
   where its initializer is not a C constant expression; otherwise nothing
   assigns its slot. */
static List Compiler._rewrite_static(
  Compiler c, List decl, Array initializers) {
  match (decl)
    case %(declare (!set ?decltype (!and (static *) (!not (* const *))))
                   (bindings *bound_list)):
      return c._defer_bindings(decltype, bound_list, initializers);
  if (!c.static_value_is_runtime(decl, NULL)) return decl;
  match (decl)
    case %(declare (!set ?decltype (!not (* const *)))
                   (bindings *bound_list)):
      return c._defer_bindings(decltype, bound_list, initializers);
  match (decl)
    case %(declare ?decltype (bindings *bound_list)):
      return c._defer_bindings(
        _unqualify_const(decltype), bound_list, initializers);
  return decl;
}

static List Compiler._defer_bindings(
  Compiler c, List decltype, List bound_list, Array initializers) {
  Array values = [];
  foreach (Ast bound, bound_list)
    values.push(c._defer_binding(decltype, bound, initializers));
  return %(declare $decltype (bindings @{values.list_free()}));
}

static List Compiler._defer_binding(
  Compiler c, List decltype, Ast bound, Array initializers) {
  match (bound) {
    case %(bind *): return bound;
    case %(op = (bind ?name ?mods) (expr ?type ?value)): {
      List declaration = %(declare $decltype (bindings (bind $name $mods)));
      Type object = declaration.type_from_ast().declared();
      if (object.car() == <const>) {
        if (!c.static_value_is_runtime(value, NULL)) return bound;
        mods = _unqualify_const(mods);
      }
      Type declared = object.canonicalize();
      Type resolved = c.sym.resolve_key(declared);
      if (resolved.is_array()) {
        if (!c.static_value_is_runtime(value, NULL)) return bound;
        match (value)
          case %(composite (commas *items)): {
            List target = $!($declared){ $name };
            List assign = c._array_block(target, resolved, items);
            List binding = _record_deferred(name, mods, assign, initializers);
            List zero = c._zero_initializer(value);
            return %(op = $binding (expr $type $zero));
          }
        return bound;
      }
      List stored = _initializer_rhs(decltype, name, mods, type, value);
      List assign = _assignment(name, type, stored);
      return _record_deferred(name, mods, assign, initializers);
    }
  }
  return bound;
}

/* Strip one initialized binding and record the assignment that replaces it. */
static List _record_deferred(
  List name, List mods, List assign, Array initializers) {
  initializers.push(%($name $assign));
  return %(bind $name $mods);
}

/* C initializes a const object only in its definition, so a definition whose
   initializer has to run drops the qualifier. The declared type still carries
   it everywhere x2c checks the object. */
static List _unqualify_const(List specifiers) =>
  specifiers.filter(%!(specifier) => specifier != <const>);

static List _initializer_rhs(
  List decltype, List binding, List mods, List type, List value) {
  if (!_is_composite(value)) return %(expr $type $value);
  List bound = %(bind $binding $mods);
  List decl_ast = %(declare $decltype (bindings $bound));
  Type cast_type = decl_ast.type_from_ast();
  if (cast_type) cast_type = cast_type.canonicalize();
  List decl = %(decl $cast_type (bindings (bind () ())));
  List literal = %(expr () $value), rhs_value = %(cast $decl $literal);
  return %(expr $cast_type $rhs_value);
}

static inline int _is_composite(List value) {
  match (value) case %(composite *): return 1;
  return 0;
}

static List _assignment(List binding, List type, List rhs) =>
  %( stmnt (expr $type (op = (expr $type (ident $binding)) $rhs)));

/* Preserve native initializer shape so C infers dimensions and checks
   designators before cached values are assigned during initialization. */
static List Compiler._zero_initializer(Compiler c, List value) {
  List zero = %(expr (int) (literal (int) "0"));
  match (value) {
    case %(expr ?type (!set ?body (initval *))): {
      List header = NULL;
      List cases = Ast.initializer_cases(body, header);
      Array zeroed = [];
      foreach (List choice, cases) {
        (List condition, List path, Type destination, List input) = choice;
        List zero = c._zero_initializer(input);
        match (zero)
          case %(expr ?type (!set ?body (composite *))):
            zero = _initializer_rhs(type, NULL, NULL, type, body);
        zeroed.push(%($condition $path $destination $zero));
      }
      return %(expr $type (initval @{zeroed.list_free()}));
    }
    case %(expr ?type (!set ?inner (composite *))):
      return %(expr $type ${c._zero_initializer(inner)});
    case %(expr ?type ?): {
      Type resolved = c.sym.resolve_key(type);
      return resolved.is_aggregate()
        ? $!($type){ { $zero } } : zero;
    }
    case %(composite (commas *items)): {
      Array zeroed = [];
      foreach (List item, items)
        zeroed.push(c._zero_initializer(item));
      return %(composite (commas @{zeroed.list_free()}));
    }
    case %((!set ?tag (!or dotinit indexinit)) ?key ?inner):
      return %($tag $key ${c._zero_initializer(inner)});
  }
  return zero;
}

// static array blocks

static List Compiler._array_block(
  Compiler c, List target, Type array, List items) {
  Array statements = [];
  foreach (List row, c.initializer_rows(array, items, target)) {
    (List original, List cases) = row;
    statements.push(c._array_row(target, original, cases));
  }
  return %(block @{statements.list_free()});
}

static List Compiler._array_row(
  Compiler c, List target, List original, List cases) {
  List terminal = original, header = NULL, source = NULL;
  while (terminal.car() == <dotinit> || terminal.car() == <indexinit>)
    terminal = terminal.caddr();
  List functions = NULL;
  match (terminal)
    case %(expr ? (!set ?body (initval *))): {
      Ast.initializer_cases(body, header);
      functions = Ast.initializer_functions(body, source);
    }
  Array assigned = [];
  List applicable = NULL;
  int unconditional = 0;
  foreach (List choice, cases) {
    List assignment =
      c._array_choice(target, choice, applicable, unconditional);
    if (assignment) assigned.push(assignment);
  }
  List code = assigned.list_free();
  if (functions && code)
    code = c._array_input(code, header, source, applicable, unconditional);
  else if (header) code = %(initcode $header $code);
  return code;
}

static List Compiler._array_choice(
  Compiler c, List target, List choice, List &applicable, int &unconditional) {
  (List condition, List path, Type type, List value) = choice;
  if (!type) return NULL;
  List tests = NULL;
  List slot = c._array_slot(target, path, tests);
  List assignment = c._array_assignment(slot, type, value, condition);
  if (condition) tests = cons(condition, tests);
  List active = NULL;
  foreach (List test, tests) {
    active = active ? $!int{ $active && $test } : test;
    assignment = c.rebuild_statement($!{ if ($test) $assignment }).cadr();
  }
  if (!active) unconditional = 1;
  else applicable = applicable
    ? $!int{ $applicable || $active } : active;
  return assignment;
}

/* Reuse ordinary indexed assignments, recursing only for explicit array
   braces. C can warn and ignore excess positional values, so writes use the
   native object's actual dimensions rather than the initializer count. */
static List Compiler._array_slot(
  Compiler c, List target, List path, List &tests) {
  List slot = target;
  tests = %();
  foreach (List frame, path.reverse()) {
    (Type owner, Symbol kind, Var selector, Type selected, List rest) = frame;
    List parent = slot;
    slot = c.initializer_slot(parent, %($frame));
    if (kind == <index>) {
      List length = %(expr (unsigned)
        (op / (expr (unsigned) (sizeof (parens $parent)))
              (expr (unsigned) (sizeof (parens $slot)))));
      tests = cons($!int{ $selector < $length }, tests);
    }
  }
  return slot;
}

static List Compiler._array_assignment(
  Compiler c, List slot, Type type, List value, List condition) {
  List inner = NULL, rhs = value;
  match (value) {
    case %(expr ? (!set ?body (composite *))): inner = body;
    case %(!set ?body (composite *)): inner = body;
  }
  Type resolved = c.sym.resolve_key(type);
  if (inner && resolved.is_array())
    return c._array_block(slot, resolved, inner.cadr().cdr());
  if (inner)
    rhs = _initializer_rhs(type, NULL, NULL, type, inner);
  if (condition) {
    List zero = _initializer_rhs(
      type, NULL, NULL, type,
      %(composite (commas (expr (int) (literal (int) "0")))));
    rhs = $!($type){ __builtin_choose_expr($condition, $rhs, $zero) };
  }
  return c.rebuild_statement($!{ $slot = $rhs; }).cadr();
}

static List Compiler._array_input(
  Compiler c, List code, List header, List source, List applicable,
  int unconditional) {
  Type type = source.cadr();
  List binding = c.sym.introduce(c.fresh_name("initializer_value"));
  List local = %(expr $type (ident $binding));
  List input = header.cadr();
  List formal = %(expr $type ${input.car()});
  code = code.search_replace(%(!quote $formal), local);
  List initial = source;
  if (!unconditional) {
    List zero = _initializer_rhs(
      type, NULL, NULL, type,
      %(composite (commas (expr (int) (literal (int) "0")))));
    initial = %(expr $type (op ? $applicable $source $zero));
  }
  List declaration = %(declare $type
    (bindings (op = (bind $binding ()) $initial)));
  return %($declaration @code);
}

// header caches

/* One translation-unit-local immutable cache in a generated header. The
   constructor eagerly establishes process-lifetime values; patched inline
   entries retain the same guard-based fallback as source-resident caches. */
typedef struct HeaderCache {
  Compiler c;
  String prefix;
  List guard, initializer;
  Map bindings;
} HeaderCache;

static List Compiler._header_cache(
  Compiler c, List header, Array ids, String prefix, String guard_name,
  String initializer_name) {
  if (!ids) return header;
  Map bindings = $auto(c._cache_bindings(ids, prefix));
  HeaderCache cache = {
    c, prefix, c.sym.reference(%($guard_name), NULL),
    c.sym.reference(%($initializer_name), NULL), bindings};
  return cache.entries(header, cache.prelude(ids));
}

static List HeaderCache.prelude(HeaderCache &h, Array ids) {
  Compiler c = h.c;
  Array declarations = [];
  foreach (List declaration, c._slot_declarations(ids, h.bindings))
    declarations.push(declaration);
  declarations.push(c.initialization_guard(h.guard));
  Array statements = [];
  foreach (int id, ids) {
    List statement = c._cache_initializer(id, h.bindings, 1);
    statements.push(_cache_refs(statement, h.bindings, NULL));
  }
  List body = c._cache_batches(statements, declarations, h.prefix);
  declarations.push(
    c._header_initializer(h.guard, h.initializer, body));
  ids.free();
  return declarations.list_free();
}

static List HeaderCache.entries(HeaderCache &h, List header, List prelude) {
  Compiler c = h.c;
  Array output = [];
  int inserted = 0;
  foreach (List node, header) {
    int replaced = 0;
    node = _cache_refs(node, h.bindings, replaced);
    int captured = node.car() == <sourceinit>;
    List function = node;
    if (captured) function = node.cadr();
    match (function)
      case %(function ?type ?bind (block *statements)):
        if (replaced) {
          if (!inserted) {
            foreach (Var item, prelude) output.push(item);
            inserted = 1;
          }
          function = _patch_initialized_entry(
            c, function, statements, h.guard, h.initializer);
          node = captured ? %(sourceinit $function) : function;
        }
    output.push(node);
  }
  return output.list_free();
}

// Header regions replace references before their private guard is installed.
static List _cache_refs(List node, Map bindings, int &?replaced) {
  if (!node) return node;
  match (node)
    case %(cache ?id): {
      if (replaced) replaced = 1;
      List binding = bindings[id];
      return %(ident $binding);
    }
  List child;
  $ast.rewrite_children(node, child, _cache_refs(child, bindings, replaced));
}

static List Compiler._header_initializer(
  Compiler c, List guard, List initializer, List statements) {
  List type = %(("__attribute__((constructor))") static void);
  List body = List.concat_n(
    3, _entry_call("x2c_initialize_protocols"), _run_once(c, guard),
    statements);
  return _initializer_function(c, type, initializer, body);
}

/** Returns the declaration of the file's initialization `guard`, which
    starts at zero. */
List Compiler.initialization_guard(Compiler c, List guard) =>
  c.rebuild_statement($!{ static int $guard = 0; }).cadr();

macro Decorator $initialized_entry(
  Function $function, Expr $guard, Expr $entry, Stmt $body...) {
  if (!$guard) $entry();
  $body...
}

List _patch_initialized_entry(
  Compiler c, List function, List body, List guard, List entry) {
  Macro shape = $initialized_entry;
  List condition = $!int{ $guard };
  List callee = %(expr ((func ((void))) void) (ident $entry));
  return c.rebuild_function(function, shape(condition, callee, body));
}

/* source caches

   Source cache slots and the deferred file-static initializers run in the
   unit's early, middle, or late initialization phase. */

/* Materialize source cache slots before ordinary file-static assignments.
   While generating String.initialize or List.initialize, a cache graph that
   requires that same canonicalizer runs late, after the initializer body;
   dependent file-static assignments move late with it. */
static List Compiler._source_cache(
  Compiler c, List source, Array ids, Map bindings, Array initializers) {
  source = c._rewrite_statics(source, initializers);
  Symbol deferred_kind = 0;
  if (c.init_fn == "String_initialize") deferred_kind = <string>;
  else if (c.init_fn == "List_initialize") deferred_kind = <cons>;
  if (!ids) {
    c._queue_statics(initializers, deferred_kind);
    return source;
  }
  Array early = [], late = [], declarations = [];
  foreach (List declaration, c._slot_declarations(ids, bindings))
    declarations.push(declaration);
  foreach (int id, ids) {
    List stmt = c._cache_initializer(id, bindings, 0);
    int deferred =
      deferred_kind && c._reaches_kind(%(cache $id), deferred_kind);
    (deferred ? late : early).push(stmt);
  }
  foreach (List stmt, c._cache_batches(early, declarations, NULL))
    c.add_init(<early>, stmt);
  foreach (List stmt, c._cache_batches(late, declarations, NULL))
    c.add_init(<late>, stmt);
  c._queue_statics(initializers, deferred_kind);
  ids.free();
  return c.place_source_prelude(source, declarations.list_free());
}

/* Large literal graphs otherwise become one enormous native basic block.
   Bound only their generated assignments, keeping their dependency order
   and initialization phase. Small caches keep the direct assignments. */
static List Compiler._cache_batches(
  Compiler c, Array statements, Array declarations, String prefix) {
  int limit = 512, count = statements.len();
  if (count <= limit) return statements.list_free();
  Array calls = [];
  String stem = prefix ? %"${prefix}initialize" : "cache_initialize";
  List type = %(("__attribute__((noinline, cold))") static void);
  for (int first = 0; first < count; first += limit) {
    Array batch = [];
    for (int i = first; i < count && i < first + limit; i++)
      batch.push(statements[i]);
    List helper = c.sym.introduce(c.fresh_name(stem));
    declarations.push(
      _initializer_function(c, type, helper, batch.list_free()));
    calls.push(c._helper_call(helper));
  }
  statements.free();
  return calls.list_free();
}

/* Whether a cache that `code` uses depends on a key of `kind`. */
static int Compiler._reaches_kind(Compiler c, List code, Symbol kind) {
  Array dependencies = c._cache_ids(code);
  if (!dependencies) return 0;
  int found = 0;
  foreach (int id, dependencies)
    if (c.id_keys[id].car() == kind) { found = 1; break; }
  dependencies.free();
  return found;
}

/* The file-static initializers of one region queue, by binding. `state` is
   1 while a binding's dependencies are visited and 2 once it is queued, and
   `phases` records the bindings queued late. */
typedef struct StaticQueue {
  Compiler c;
  Map pending, state, phases;
  Array initializers;
  Symbol deferred_kind;
} StaticQueue;

/* Queue a stable dependency walk. Dependencies precede their consumers, and
   independent roots retain source order. A dependency queued late moves every
   consuming initializer late as well. */
static void Compiler._queue_statics(
  Compiler c, Array initializers, Symbol deferred_kind) {
  Map pending = {}, state = {}, phases = {};
  foreach (List initializer, initializers) {
    Var definitions;
    if (!pending.try_get(initializer.car(), definitions))
      pending[initializer.car()] = definitions = [];
    definitions.array().push(initializer);
  }
  StaticQueue queue = {c, pending, state, phases, initializers, deferred_kind};
  foreach (List initializer, initializers) queue.visit(initializer.car());
}

static void StaticQueue.visit(StaticQueue &q, List binding) {
  Var status;
  if (q.state.try_get(binding, status)) {
    if (status == 2) return;
    q.report_cycle();
  }
  q.state[binding] = 1;
  Array definitions = q.pending[binding];
  int late = 0;
  Var stored;
  if (q.c.static_init_deps.try_get(binding, stored)) {
    List dependencies = stored;
    foreach (List dependency, dependencies) {
      if (dependency in q.pending) {
        q.visit(dependency);
        Var phase = q.phases[dependency];
        if (phase is not void && phase) late = 1;
      }
    }
  }
  if (q.deferred(definitions)) late = 1;
  q.add_calls(definitions, late);
  q.phases[binding] = late;
  q.state[binding] = 2;
}

static int StaticQueue.deferred(StaticQueue &q, Array definitions) {
  if (!q.deferred_kind) return 0;
  foreach (List initializer, definitions)
    if (q.c._reaches_kind(initializer.cadr(), q.deferred_kind)) return 1;
  return 0;
}

static void StaticQueue.add_calls(
  StaticQueue &q, Array definitions, int late) {
  /* Each branch of a conditional group may define the binding. A definition
     runs under the directives that enclose it, since a disabled branch
     defines no helper. */
  foreach (List initializer, definitions) {
    List helper = initializer.caddr(), arms = initializer[3];
    List call = q.c._helper_call(helper);
    foreach (List statement, preproc_within_arms(arms, %($call)))
      q.c.add_init(late ? <late> : <mid>, statement);
  }
}

static void StaticQueue.report_cycle(StaticQueue &q) {
  Compiler c = q.c;
  Array notes = [], List first = NULL;
  foreach (List initializer, q.initializers)
    match (initializer)
      case %(?binding *): {
        Var status;
        if (!q.state.try_get(binding, status) || status != 1) continue;
        if (!first) first = binding;
        String name = binding_identity_spelling(binding);
        if (name) notes.push(%"initializer: $name");
      }
  Token token = NULL;
  Var token_index;
  if (first && c.init_tokens.try_get(first, token_index)) {
    Token tokens = c.tokenizer.tokens;
    token = tokens + token_index.integer();
  }
  $report.cache.init_cycle(c, token, notes.list_free());
}

// cache slots and values

/* Slot names belong to this region's reachable order. Semantic cache ids
   continue to index the unit's retained literal graph. */
static Map Compiler._cache_bindings(Compiler c, Array ids, String prefix) {
  Map bindings = {};
  int slot = 0;
  foreach (Var id, ids) {
    String name = prefix ? %"$prefix$slot" : %"_$slot";
    bindings[id] = c.sym.reference(%($name), NULL);
    slot++;
  }
  return bindings;
}

/* The static List, String, and Var slot declarations for `ids`, in that
   order, each in the descending slot order `_split_ids` keeps. */
static List Compiler._slot_declarations(Compiler c, Array ids, Map bindings) {
  List (list_ids, string_ids, var_ids) = _split_ids(c.id_keys, ids);
  Array declarations = [];
  List declaration = _declare_slots(list_ids, "List", bindings);
  if (declaration) declarations.push(declaration);
  declaration = _declare_slots(string_ids, "String", bindings);
  if (declaration) declarations.push(declaration);
  declaration = _declare_slots(var_ids, "Var", bindings);
  if (declaration) declarations.push(declaration);
  return declarations.list_free();
}

/* Split the ordered cache ids by declaration type. Each list keeps the
   descending slot order the emitted declarations use. */
static List _split_ids(Array keys, Array ids) {
  List list_ids = %(), string_ids = %(), var_ids = %();
  foreach (int id, ids) {
    List key = keys[id];
    match (key) {
      case %(cons *): {
        list_ids = cons(id, list_ids);
        continue;
      }
      case %(string ?): {
        string_ids = cons(id, string_ids);
        continue;
      }
      case %(var ?): {
        var_ids = cons(id, var_ids);
        continue;
      }
    }
    __builtin_unreachable();
  }
  return %($list_ids $string_ids $var_ids);
}

static List _declare_slots(List ids, String type, Map bindings) {
  if (!ids) return NULL;
  Array values = [];
  foreach (Var id, ids) {
    List binding = bindings[id];
    values.push(%(bind $binding ()));
  }
  List binds = values.list_free();
  return %(declare (static $type) (bindings @binds));
}

static List Compiler._cache_initializer(
  Compiler c, int id, Map bindings, int header) {
  match (c.id_keys[id]) {
    case %(string ?value):
      return c._cache_assignment(id, value, %("String"), bindings, header);
    case %(var ?value):
      return c._cache_assignment(id, value, %("Var"), bindings, header);
    case %(!set ?value (cons *)):
      return c._cache_assignment(id, value, %("List"), bindings, header);
  }
  __builtin_unreachable();
}

static List Compiler._cache_assignment(
  Compiler c, int id, List value, List type, Map bindings, int header) {
  List binding = bindings[id];
  List rhs = c.convert_expression(
    c._cache_value(value, header ? bindings : NULL), type);
  return _assignment(binding, type, rhs);
}

static List Compiler._cache_value(Compiler c, List expr, Map bindings) {
  if (!expr) return NULL;
  match (expr) {
    case %(cons ?captured_head ?captured_tail): {
      List head = c._cache_value(captured_head, bindings);
      List tail = c._cache_value(captured_tail, bindings);
      List cons_binding = c.sym.reference(%("cons"), NULL);
      return %(expr ("List")
        (call (expr ((func (("Var") ("List")) "List")) (ident $cons_binding))
              ( args $head $tail ))
      );
    }
    case %((!or array varray) *):
      return %(expr ("Array") ${transform_array_literal(c, expr)});
    case %((!or map vmap) *):
      return %(expr ("Map") ${transform_map_literal(c, expr)});
    case %(string *):
      // Keep String initializer nodes; literal folding is handled elsewhere.
      return expr;
    case %(cache ?id): {
      List val = c.id_keys[id], reference = expr;
      if (bindings) {
        List binding = bindings[id];
        reference = %(ident $binding);
      }
      match (val) {
        case %(string ?): return %(expr ("String") $reference);
        case %(var ?):    return %(expr ("Var") $reference);
        case %(cons *):   return %(expr ("List") $reference);
      }
      __builtin_unreachable();
    }
  }
  return expr;
}
