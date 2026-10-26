/*  transactions.x -- symbol transactions */

/** Sets `map[key]` so that an active semantic transaction can restore it.
    Semantic writes to scope, file-static, and binding-fact maps use this.
*/
void Sym.put(Sym s, Map map, Var key, Var value) {
  _remember(s, map, key);
  map[key] = value;
}

/** Deletes `key` from `map` so that an active transaction can restore it. */
void Sym.drop(Sym s, Map map, Var key) {
  _remember(s, map, key);
  map.del(key);
}

static void _remember(Sym s, Map map, Var key) {
  if (!s.transactions) return;
  Var value = void;
  map.try_get(key, value);
  SymUndo row = { .map = map, .key = key, .value = value };
  s.undo.push(&row);
}

/* semantic transactions

   Binding a macro's syntax runs in a transaction, so a failed expansion
   leaves the symbol table as it was. Writes change the maps in place and
   record the rows they replace in the symbol table's undo log, so beginning
   and committing cost nothing per row the unit already holds. */

/** Begins a reversible transaction over the current semantic scope.

    The transaction restores the current scope maps, file-static and binding
    facts, binding and generated-name counters, initializer names, and the
    parser's ancestors and placements. It does not snapshot parser position
    or other compiler state.
*/
SymTxn Compiler.begin_semantic_transaction(Compiler c) {
  SymTxn transaction = { .c = c };
  transaction.scope_index = c.sym.scopes.len() - 1;
  _save(transaction, *_scope_at(c.sym, transaction.scope_index));
  if (transaction.extended) _save_effects(transaction);
  if (c.source_facts && c.source_primary) _save_sources(transaction);
  /* Related compilers with their own symbol tables share these counters,
     so the transaction stages a copy instead of logging their writes. */
  c.names.counters = c.names.counters.copy();
  c.sym.transactions++;
  transaction.active = 1;
  return transaction;
}

static void _save(SymTxn &s, SymScope scope) {
  Compiler c = s.c;
  s.scope = scope;
  s.mark = c.sym.undo.len();
  s.meta_group_size = c.meta_group.len();
  s.ancestors = c.ancestors.len();
  s.placements = c.placements.len();
  s.counters = c.names.counters;
  s.statics = c.sym.statics;
  s.binding_facts = c.semantic_binding_facts();
  s.next_binding = c.names.next_binding;
  s.local_macro_names = c.sym.local_macro_names;
  s.initializer_name = c.init_fn;
  s.shutdown_name = c.fini_fn;
  s.extended = c.macro_application > 0;
}

static void _save_effects(SymTxn &s) {
  Compiler c = s.c;
  s.adapters = c.names.adapters;
  s.pending = c.pending.checkpoint();
  s.origin_count = c.origins.len();
  s.origin = c.origin;
  s.needs_exception = c.needs_exception;
  c.names.adapters = c.names.adapters.copy();
}

static void _save_sources(SymTxn &s) {
  s.source_definitions = s.c.source_definitions.copy();
  s.source_occurrences = s.c.source_occurrences.len();
}

/* Rollback restores the active scope's maps, file statics, binding facts,
   and declaration source metadata. Base-scope identities also roll back
   with their binding facts and counter. Rows of other maps stay in the log for
   an enclosing transaction. */
static int _tracks(SymTxn &s, Map map) {
  if (_same(map, s.scope.symbols) || _same(map, s.scope.bindings) ||
      _same(map, s.scope.enumerators) || _same(map, s.scope.macros) ||
      _same(map, s.statics) || _same(map, s.binding_facts) ||
      _same(map, s.c.macros) || _same(map, s.c.kw_aliases)) return 1;
  if (s.c.source_facts && _same(map, s.c.source_declarations)) return 1;
  Sym sym = s.c.sym;
  for (int i = 0; i < sym.base_scopes; i++)
    if (_same(map, _scope_at(sym, i).bindings)) return 1;
  return 0;
}

static int _same(Map a, Map b) => (void *) a == (void *) b;

/** Returns whether the transaction's active scope changed its macro map. */
int SymTxn.local_macros_changed(SymTxn &s) {
  SymScope *scope = _scope_at(s.c.sym, s.scope_index);
  Map before = s.scope.macros, after = scope.macros;
  if (before == NULL || after == NULL) return !_same(before, after);
  Block undo = s.c.sym.undo;
  SymUndo *rows = undo.bytes;
  Map seen = {};
  for (int i = s.mark; i < (int) undo.len(); i++) {
    SymUndo row = rows[i];
    if (!_same(row.map, after) || row.key in seen) continue;
    seen[row.key] = 1;
    if (row.value is void || row.value != after[row.key]) return 1;
  }
  return 0;
}

/** Returns whether a semantic transaction is open. */
int Sym.transacting(Sym s) => s.transactions > 0;

// commit and rollback

/** Publishes an active semantic transaction and makes rollback a no-op.
    Its writes are already in the scope maps, so code holding a borrowed
    map observes a committed expansion. An absent or inactive transaction
    has no effect.
*/
void SymTxn.commit(SymTxn &?s) {
  if (!s) return;
  if (!s.active) return;
  if (s.extended) {
    Compiler c = s.c;
    Map adapters = c.names.adapters;
    c.names.adapters = s.adapters;
    s.adapters.merge(adapters);
  }
  _finish(s);
}

/* Completing the outermost transaction empties the undo log. */
static void _finish(SymTxn &s) {
  s.active = 0;
  Sym sym = s.c.sym;
  if (!--sym.transactions) sym.undo.clear();
}

/** Commits an active transaction, retaining the original counters map.
    The caller may then release the transaction's construction scope.
    Parsing and evaluation must allocate outside that temporary scope.
*/
void SymTxn.commit_transient(SymTxn &s) {
  Compiler c = s.c;
  Map counters = c.names.counters;
  s.commit();
  c.names.counters = s.counters;
  s.counters.merge(counters);
}

/** Restores every semantic value captured by an active transaction.
    An absent or inactive transaction has no effect.
*/
void SymTxn.rollback(SymTxn &?s) {
  if (!s) return;
  if (!s.active) return;
  Compiler c = s.c;
  _undo(s);
  _restore(s);
  if (s.extended) _restore_effects(s);
  if (c.source_facts && c.source_primary) _restore_sources(s);
  _finish(s);
}

/* Restores the logged rows this transaction tracks, newest first, and
   keeps the others in order. */
static void _undo(SymTxn &s) {
  Block undo = s.c.sym.undo;
  SymUndo *rows = undo.bytes;
  int end = undo.len(), kept = s.mark;
  for (int i = end - 1; i >= s.mark; i--) {
    SymUndo row = rows[i];
    if (!_tracks(s, row.map)) continue;
    if (row.value is void) row.map.del(row.key);
    else row.map[row.key] = row.value;
  }
  for (int i = s.mark; i < end; i++)
    if (!_tracks(s, rows[i].map)) rows[kept++] = rows[i];
  undo.truncate(kept);
}

static void _restore(SymTxn &s) {
  Compiler c = s.c;
  SymScope *scope = _scope_at(c.sym, s.scope_index);
  *scope = s.scope;
  c.sym.statics = s.statics;
  c.sym.binding_facts = s.binding_facts;
  c.names.next_binding = s.next_binding;
  c.meta_group.resize(s.meta_group_size);
  c.ancestors.truncate(s.ancestors);
  c.placements.resize(s.placements);
  c.sym.local_macro_names = s.local_macro_names;
  c.names.counters = s.counters;
  c.init_fn = s.initializer_name;
  c.fini_fn = s.shutdown_name;
}

static void _restore_effects(SymTxn &s) {
  Compiler c = s.c;
  c.names.adapters = s.adapters;
  c.pending.restore(s.pending);
  c.origins.resize(s.origin_count);
  c.origin = s.origin;
  c.needs_exception = s.needs_exception;
}

/* Restore source definitions in place, removing rows the transaction added. */
static void _restore_sources(SymTxn &s) {
  Compiler c = s.c;
  c.source_occurrences.resize(s.source_occurrences);
  Map original = c.source_definitions, staged = s.source_definitions;
  Array keys = auto original.keys();
  foreach (Var key in keys) if (!(key in staged)) original.del(key);
  original.merge(staged);
}
