/*  scopes.x -- symbol scopes */

/** Creates the empty symbol table that compiler `c` owns. */
Sym Sym.new(Compiler c) {
  Sym s = xcalloc(1, sizeof(struct Sym));
  s.c = c;
  s.binding_facts = {};
  s.scopes = Block.new(sizeof(SymScope));
  s.statics = {};
  s.prefixed = {};
  s.undo = Block.new(sizeof(SymUndo));
  return s;
}

module SymScope *_scope_at(Sym s, int index) {
  int count = s.scopes.len();
  if (index < 0) index += count;
  if (index < 0 || index >= count) return NULL;
  SymScope *scopes = s.scopes.bytes;
  return scopes + index;
}

/** Resets symbol state to one base scope backed by `globals`.

    Later definitions mutate that caller-supplied map.
*/
void Sym.reset(Sym s, Map globals) {
  _clear_symbols(s, globals, 1);
  _push_symbols(s, s.globals);
}

/** Resets symbol state to read `base` below the writable scope `overlay`.

    Later definitions mutate `overlay`; `base` is only read.
*/
void Sym.reset_overlay(Sym s, Map base, Map overlay) {
  _clear_symbols(s, overlay, 2);
  _push_symbols(s, base != NULL ? base : {});
  _push_symbols(s, s.globals);
}

static void _clear_symbols(Sym s, Map globals, int base_scopes) {
  s.scopes.clear();
  s.globals = globals != NULL ? globals : {};
  s.statics = {};
  s.prefixed = {};
  s.base_scopes = base_scopes;
  s.local_macro_names = 0;
  s.aliases = 0;
  s.binding_facts = {};
}

static void _push_symbols(Sym s, Map symbols) {
  struct SymScope scope = {
    .symbols = symbols, .bindings = {}, .enumerators = {}};
  s.scopes.push(&scope);
}

/** Pushes a new empty lexical scope. */
void Sym.push_new_scope(Sym s) => _push_symbols(s, {});

/** Pushes a caller-supplied lexical scope while retaining its map objects. */
void Sym.push_scope(Sym s, SymScope scope) => s.scopes.push(&scope);

/** Pops the innermost scope, or returns an empty scope when none exists. */
SymScope Sym.pop_scope(Sym s) {
  struct SymScope scope = { 0 };
  s.scopes.try_pop(&scope);
  if (scope.macros != NULL) s.local_macro_names -= scope.macros.len();
  s.aliases -= scope.aliases;
  return scope;
}

/** Returns the index of the innermost scope whose symbols hold `key`, or
    -1 when none does.
*/
int Sym.declaring_scope(Sym s, List key) {
  for (int i = (int) s.scopes.len() - 1; i >= 0; i--)
    if (key in _scope_at(s, i).symbols) return i;
  return -1;
}

/** Returns the number of semantic scopes, including base scopes. */
int Sym.scope_count(Sym s) => s.scopes.len();

/** Returns the number of base scopes, which hold file-scope declarations. */
int Sym.base_scope_count(Sym s) => s.base_scopes;

/** Returns whether any open scope defines an alias row. */
int Sym.has_aliases(Sym s) => s.aliases != 0;

/** Returns whether declarations currently bind at file scope. */
int Sym.at_file_scope(Sym s) => (int) s.scopes.len() <= s.base_scopes;

/** Sets aside the local scopes now open, so declarations bind at file
    scope until `Sym.reopen_scopes` restores the returned scopes.
*/
Block Sym.close_local_scopes(Sym s) {
  Block local = Block.new(sizeof(SymScope));
  if (s.at_file_scope()) return local;
  local.append(_scope_at(s, s.base_scopes), s.scopes.len() - s.base_scopes);
  s.scopes.truncate(s.base_scopes);
  return local;
}

/** Reopens the local scopes `Sym.close_local_scopes` set aside. */
void Sym.reopen_scopes(Sym s, Block local) {
  s.scopes.append(local.bytes, local.len());
  local.free();
}

// symbol maps

/** Returns the mutable global symbol map supplied to the latest reset. */
Map Sym.global_symbols(Sym s) => s.globals;

/** Copies all base-scope symbols into a fresh map in source order.

    Package collection uses this so it resolves against the prelude and the
    importing unit's already-visible includes without mutating either.
*/
Map Sym.base_symbols(Sym s) {
  Map seed = {};
  for (int i = 0; i < s.base_scopes; i++) seed.merge(_scope_at(s, i).symbols);
  return seed;
}

/** Returns the current scope's mutable symbol map, or `NULL`. */
Map Sym.current_symbols(Sym s) {
  SymScope *scope = _scope_at(s, -1);
  return scope ? scope.symbols : NULL;
}

/** Returns a fresh map of the base symbols with the current scope's rows
    merged in.
*/
Map Sym.unit_symbols(Sym s) {
  Map symbols = s.base_symbols();
  if (!s.at_file_scope()) symbols.merge(s.current_symbols());
  return symbols;
}

/** Returns the borrowed set of file-static declaration keys. */
Map Sym.file_statics(Sym s) => s.statics;

/** Marks a declaration key as file-static. */
void Sym.mark_static(Sym s, List key) => s.put(s.statics, key, 1);

/** Returns the visible one-part source names and their semantic types.
    Inner scopes win. The result is a fresh List; types remain borrowed.
*/
List Sym.visible_symbols(Sym s) {
  Map seen = {};
  Array rows = [];
  for (int i = (int) s.scopes.len() - 1; i >= 0; i--) {
    SymScope *scope = _scope_at(s, i);
    foreach (Var (key, value) in scope.symbols)
      if ((key ~= %(?(String name))) && _unseen(seen, name))
        rows.push($(name, value));
    if (scope.macros != NULL)
      foreach ((Var name, List definition) in scope.macros)
        if (name is <string> && _unseen(seen, name))
          rows.push($(name, _macro_kind(definition)));
  }
  return rows.list_free();
}

static int _unseen(Map seen, Var name) {
  if (name in seen) return 0;
  seen[name] = 1;
  return 1;
}

static Symbol _macro_kind(Var definition) {
  Symbol kind = definition is <list> ? definition.list().assoc(<kind>) : 0;
  return kind == <type> ? <typemacro> : <macro>;
}

// local macros

/** Defines or replaces a macro in the active lexical scope.

    Replacing a name already defined in this scope does not increase the
    local macro count.
*/
void Sym.define_macro(Sym s, Atom name, List definition) {
  SymScope *scope = _scope_at(s, -1);
  if (scope.macros == NULL) scope.macros = {};
  if (!(name in scope.macros)) s.local_macro_names++;
  s.put(scope.macros, name, definition);
}

/** Returns whether any lexical scope contains a local macro definition. */
int Sym.has_local_macros(Sym s) => s.local_macro_names != 0;

/** Returns the innermost visible local macro named `name`, or `NULL`. */
List Sym.lookup_macro(Sym s, Atom name) {
  Var definition;
  for (int i = (int) s.scopes.len() - 1; i >= s.base_scopes; i--) {
    SymScope *scope = _scope_at(s, i);
    if (scope.macros != NULL && scope.macros.try_get(name, definition))
      return definition;
  }
  return NULL;
}

/** Returns the active macro definition's borrowed local map, or `NULL`. */
Map Compiler.macro_definition_locals(Compiler c) {
  Var stored = c.macro_holes[%(locals)];
  return stored is <map> ? stored : NULL;
}

/** Reports whether `binding` is a local of the active macro definition or
    of a template that encloses it; a nested definition's literal names
    share the enclosing template's names.
*/
int Compiler.macro_template_local(Compiler c, List binding) {
  Var holes = c.macro_holes;
  while (holes is <map>) {
    Map current = holes;
    Var locals = current[%(locals)];
    if (locals is <map> && binding in (Map) locals) return 1;
    holes = current[%(enclosing)];
  }
  return 0;
}
