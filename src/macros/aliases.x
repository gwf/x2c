/*  aliases.x -- lexical expression aliases

    `alias expression as name` names a parsed expression until the name's
    scope ends. Each use of the name in expression position stands for the
    parsed expression as one grouped operand, so an unused alias evaluates
    nothing and every use keeps the bindings the expression had at the
    declaration. Inside a function an alias is a row of its Sym scope. At
    file scope, and in an aggregate, enumerator, or wrapper body, it is an
    entry of the unit's macro state: a file-scope entry follows macro
    visibility through includes, and a body's entries end at its closing
    brace.

    Sym scopes cannot hold the second kind. File-scope Sym rows persist
    from collection into the full parse and every including unit, while an
    alias must start at its declaration and cross an include as a
    compile-time effect, as a macro does. An aggregate or enumerator body
    opens no Sym scope, because its members declare into the enclosing
    one; the body level tells its aliases from those of the scope around
    it at the same Sym depth. The table therefore owns what Sym owns for
    ordinary names: conflicts at file scope, including those an include
    brings, and the file a `static` alias belongs to.
*/

/* aliases diagnostics. */

static macro Stmt $fail.macros_alias_expression(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "alias requires an expression",
    $site, NULL);

static macro Stmt $fail.macros_alias_end(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected ';' or '{' after an alias expression",
    $site, NULL);

static macro Stmt $problem.macros_alias_included(
  Expr $c, Expr $site, Expr $name) =>
  $c.report_problem(
    <parse>, %"declaration '$($name)' is already bound",
    $site, %("this include aliases '$($name)'"));

static macro Stmt $fail.macros_unalias_missing(
  Expr $c, Expr $site, Expr $name) =>
  $c.report_error(
    <parse>, %"no alias '$($name)' to remove in this scope",
    $site, %("an alias of an enclosing scope ends with that scope"));

static macro Stmt $fail.macros_unalias_governed(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "unalias cannot be the body of a statement",
    $site, NULL);

static macro Stmt $fail.macros_alias_governed(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "alias declaration cannot be the body of a statement",
    $site, %("give the alias a braced body"));

// recognition

/** Reports whether the cursor begins an alias or its removal. An alias is
    the word `alias`, or at file scope `static alias`, then an expression
    followed by `as` or a braced body; a removal is `unalias name;`. Each
    word stays an ordinary name where it continues an operand, as in
    `alias = value;`, and where it names a type that no `as` follows. This
    query does not consume tokens.
*/
int Compiler.alias_form_starts(Compiler c) {
  if (c.at_word("unalias")) return _unalias_starts(c);
  Token word = c.token;
  if (word.type == <static> && c.sym.at_file_scope())
    word = Token.skip_trivia(word + 1);
  if (word.type != <ident> || word.text != "alias") return 0;
  Token next = Token.skip_trivia(word + 1);
  if (_continues_operand(next.type)) return 0;
  Type named = c.sym.get(%("alias"));
  for (Token token = next; token.type != <eof> && token.type != <;>;
       token = token.after_group()) {
    if (token.type == <ident> && token.text == "as") return 1;
    if (token.type == <"{">) return !named || !named.is_typedef();
    if (token.type == <"}"> || token.type.is_assignment_op()) return 0;
  }
  return 0;
}

static int _unalias_starts(Compiler c) {
  Token name = Token.skip_trivia(c.token + 1);
  Type named = c.sym.get(%("unalias"));
  return name.type == <ident> && Token.skip_trivia(name + 1).type == <;> &&
         (!named || !named.is_typedef());
}

static int _continues_operand(Symbol type) =>
  type.is_assignment_op() || type in _operand_tails ||
  (type.binary_precedence() && !(type in _prefix_operators));

static const SymbolSet _operand_tails = %<<. -> ++ -- ; , ) ] } ?>>;
static const SymbolSet _prefix_operators = %<<* & - +>>;

// declarations

/* One alias head: `[static] alias expression [as name]`, stopped at its
   `;` or `{`. An unnamed alias names `_`. */
module typedef struct AliasHead {
  Token start;
  int storage;
  List expression;
  String name;
} AliasHead;

static AliasHead _head(Compiler c) {
  AliasHead head = { .start = c.token, .storage = c.test(<static>) };
  c.next();
  if ((c.peek(0) == <"{"> && c.peek(1) == <"}">) ||
      c.peek(0) == <;> || c.peek(0) == <eof>)
    $fail.macros_alias_expression(c, c.token);
  head.expression = c.parse_expression();
  head.name = _alias_name(c);
  if (c.peek(0) != <;> && c.peek(0) != <"{">)
    $fail.macros_alias_end(c, c.token);
  return head;
}

/* The name after `as`, or `_` when the alias names none. Only a braced
   alias can omit it: recognition requires `as` before a `;`. */
static String _alias_name(Compiler c) {
  if (!c.take_word("as")) return "_";
  if (c.peek(0) != <ident>)
    $fail.parse_alias_name(c, c.token);
  String name = c.token.text;
  c.next();
  return name;
}

/** Parses an alias or its removal in a function body or a template. The
    semicolon form and `unalias` change the current scope and return
    `(seq)`; they require block position, which `block` reports. The braced
    form returns its block, with the name defined in a scope around it.
*/
List Compiler.parse_alias_statement(Compiler c, int block) {
  if (c.at_word("unalias")) return _unalias(c, block);
  AliasHead head = _head(c);
  if (c.test(<;>)) {
    if (!block) $fail.macros_alias_governed(c, head.start);
    _define_local(c, head);
    return %(seq);
  }
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  c.sym.define_alias(head.name, head.expression);
  c.next();
  return c.parse_compound_statement();
}

static void _define_local(Compiler c, AliasHead &head) {
  if ($(head.name) in c.sym.current_symbols())
    $fail.parse_decl_bound(c, head.start, head.name);
  c.sym.define_alias(head.name, head.expression);
}

/** Parses an alias or its removal at file scope. A semicolon alias returns
    NULL; its name stays visible to the rest of the unit and, unless it is
    `static`, to the files that include this one. `unalias` also returns
    NULL. A braced alias returns `(seq ...)` of the
    top-level forms it wraps, which keep their file-scope placement while
    the name ends at the closing brace. Collection, with `skip_body`, reads
    the wrapped forms as it reads any other. Inside a template the name is
    the template's own, as at block scope.
*/
List Compiler.parse_alias_declaration(Compiler c, int skip_body) {
  if (!c.sym.at_file_scope()) return _template_declaration(c, skip_body);
  if (c.at_word("unalias")) {
    _unalias(c, 1);
    return NULL;
  }
  AliasHead head = _head(c);
  if (c.test(<;>)) {
    _declare(c, head, skip_body);
    return NULL;
  }
  Map mark = c.enter_alias_body();
  defer c.leave_alias_body(mark);
  _declare(c, head, skip_body);
  c.next();
  return _wrapped_forms(c, skip_body);
}

static List _template_declaration(Compiler c, int skip_body) {
  if (c.at_word("unalias")) return _unalias(c, 1);
  AliasHead head = _head(c);
  if (c.test(<;>)) {
    _define_local(c, head);
    return %(seq);
  }
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  c.sym.define_alias(head.name, head.expression);
  c.next();
  return _wrapped_forms(c, skip_body);
}

/* Directives between the forms stay among them. */
static List _wrapped_forms(Compiler c, int skip_body) {
  Array forms = [];
  loop {
    List directives = c.leading_preproc();
    foreach (List directive in directives) forms.push(directive);
    if (c.peek(0) == <"}"> || c.peek(0) == <eof>) break;
    List form = skip_body ? NULL : c.replay_declaration_source();
    if (!form) form = c.parse_top_level_mode(skip_body);
    if (form && form.car() == <seq>)
      foreach (List item in form.cdr()) forms.push(item);
    else if (form) forms.push(form);
  }
  c.expect(<"}">);
  return %(seq @(forms.list_free()));
}

/** Parses an alias among the members of an aggregate or enum body, where
    `position` is `<field>` or `<enumerator>` and `context` is the
    aggregate type. Its name ends with the body. A braced alias returns
    `(seq ...)` of the members it wraps; a semicolon alias and `unalias`
    return `(seq)`.
*/
List Compiler.parse_alias_member(
  Compiler c, Symbol position, List context) {
  if (c.at_word("unalias")) return _unalias(c, 1);
  AliasHead head = _head(c);
  if (c.test(<;>)) {
    _declare(c, head, 0);
    return %(seq);
  }
  Map mark = c.enter_alias_body();
  defer c.leave_alias_body(mark);
  _declare(c, head, 0);
  c.next();
  // The wrapper owns the brace, so the members declare into its body.
  List members = position == <enumerator> ? c.parse_enumerators(context)
                                          : c.parse_fields(context);
  c.expect(<"}">);
  return %(seq @members);
}

/* An entry is `(declared depth level expression)`, with the Sym scope
   count and body level of its declaration, or `(imported frozen)` for a
   public alias an include delivered, which belongs to file scope. An
   entry that shadows an outer entry of its key ends with that entry. A
   `static` alias is keyed by its file's prefix, empty outside a module
   unit, and its name, so each file of the unit keeps its own; a public
   alias is keyed by its name alone. Two aliases that one file sees in one
   scope conflict. A semicolon alias at file scope also conflicts with an
   earlier file-scope declaration of its name, which collection, reading
   declarations in source order, reports; a later one reports itself. An
   included file's walk also sees its includer's names, which its include
   line checks instead. A public alias records its compile-time effect for
   including files. */
static void _declare(Compiler c, AliasHead &head, int collecting) {
  if (_same_scope(c, _entry(c, head.name, NULL)))
    $fail.parse_decl_bound(c, head.start, head.name);
  int depth = c.sym.scope_count(), level = c.alias_level;
  int file_scope = !level && c.sym.at_file_scope();
  if (collecting && file_scope && !c.interface_provider &&
      c.sym.get($(head.name)))
    $fail.parse_decl_bound(c, head.start, head.name);
  Var key = head.storage ? _private_key(c, head.name) : head.name;
  _install(c, key, %(declared $depth $level $(head.expression)));
  if (file_scope && !head.storage)
    _record_compile_time_effect(
      c, %(compile-time alias $(head.name)
        $(c.freeze_declaration_syntax(head.expression))), head.start);
}

static List _private_key(Compiler c, String name) {
  String file = c.file_prefix();
  return $(file ? file : "", name);
}

/* A public alias is keyed by its name alone; a `static` one by its file's
   prefix and its name. */
static int _public_key(Var key) => key is <string>;

/* `unalias name;` removes the alias the current scope declares, and the
   name means what it meant before that alias. Removing a public alias at
   file scope is a compile-time effect for including files. */
static List _unalias(Compiler c, int block) {
  Token start = c.token;
  c.next();
  String name = c.token.text;
  c.next();
  c.expect(<;>);
  if (!block) $fail.macros_unalias_governed(c, start);
  List row = c.sym.current_binding($(name));
  if (row && c.fact(%(alias $row))) {
    c.sym.undefine_alias(name);
    return %(seq);
  }
  Var key;
  if (!_same_scope(c, _entry(c, name, key)))
    $fail.macros_unalias_missing(c, start, name);
  _remove(c, key);
  if (!c.alias_level && c.sym.at_file_scope() && _public_key(key))
    _record_compile_time_effect(c, %(compile-time unalias $name), start);
  return %(seq);
}

static int _same_scope(Compiler c, List entry) {
  match (entry) {
    case %(imported *): return !c.alias_level && c.sym.at_file_scope();
    case %(declared ?(int depth) ?(int level) *):
      return depth == c.sym.scope_count() && level == c.alias_level;
  }
  return 0;
}

/* Entries live in one Map under `<alias>`, which each declaration
   replaces with a copy, so a body restores its outer entries by restoring
   the Map it started with. An entry keeps the entry it shadows, so its
   removal reveals the enclosing meaning before the body ends. */
static void _install(Compiler c, Var key, List entry) {
  Map table = _table(c);
  table = table ? table.copy() : {};
  Var shadowed;
  if (table.try_get(key, shadowed)) entry = entry.append($(shadowed));
  table[key] = entry;
  c.sym.put(c.macros, <alias>, table);
}

static void _remove(Compiler c, Var key) {
  Map table = _table(c).copy();
  List shadowed = _shadowed(table[key]);
  if (shadowed) table[key] = shadowed;
  else table.del(key);
  c.sym.put(c.macros, <alias>, table);
}

static List _shadowed(List entry) {
  match (entry) {
    case %(declared ? ? ? ?outer): return outer;
    case %(imported ? ?outer): return outer;
  }
  return NULL;
}

static Map _table(Compiler c) {
  Var stored;
  return c.macros.try_get(<alias>, stored) ? stored : NULL;
}

/* The entry of `name` where the cursor stands, and its `key`: the current
   file's `static` alias, unless a closer body alias of that name shadows
   it, else the alias every file sees. */
static List _entry(Compiler c, String name, Var &?key) {
  Map table = _table(c);
  if (!table) return NULL;
  Var entry, own = _private_key(c, name);
  if (table.try_get(own, entry)) {
    Var shared;
    if (table.try_get(name, shared) && _inner_entry(shared, entry)) {
      own = name;
      entry = shared;
    }
    if (key) key = own;
    return entry;
  }
  if (key) key = name;
  return table.try_get(name, entry) ? entry : NULL;
}

static int _inner_entry(List inner, List outer) {
  if (inner ~= %(declared ?(int depth) ?(int level) *) &&
      outer ~= %(declared ?(int prior_depth) ?(int prior_level) *))
    return depth > prior_depth ||
           (depth == prior_depth && level > prior_level);
  return 0;
}

/** Starts a declaration body whose aliases end at its closing brace, and
    returns the alias state that `Compiler.leave_alias_body` restores.
*/
Map Compiler.enter_alias_body(Compiler c) {
  c.alias_level++;
  return _table(c);
}

/** Ends a declaration body, restoring the aliases visible before it. */
void Compiler.leave_alias_body(Compiler c, Map mark) {
  c.alias_level--;
  if ((void *) _table(c) == (void *) mark) return;
  if (mark) c.sym.put(c.macros, <alias>, mark);
  else c.sym.drop(c.macros, <alias>);
}

/* An included file's public alias arrives as its frozen expression, which
   is thawed when the name is first used. It conflicts with an alias the
   including file already has at file scope, and with a file-scope name the
   full parse has already bound there. The full parse records that at the
   include line and continues installing the include's definitions. */
module void _install_imported_alias(Compiler c, String name, List frozen) {
  if (_full_parse(c) &&
      (_same_scope(c, _entry(c, name, NULL)) ||
       c.sym.current_binding($(name))))
    $problem.macros_alias_included(c, c.token, name);
  _install(c, name, %(imported $frozen));
}

/* Whether `c` is parsing its unit in full. The full parse alone holds the
   include effects it installs at include lines; collection, prelude
   installation, and a cold walk of an included file leave them unset. */
static int _full_parse(Compiler c) => c.included_effects != NULL;

/* An included file's removal of its public alias. */
module void _remove_imported_alias(Compiler c, String name) {
  Map table = _table(c);
  if (table && name in table) _remove(c, name);
}

/** Reports whether the current scope declares an alias named `name`,
    including a file-scope alias an include delivered. A declaration of that
    name in the same scope conflicts with it.
*/
int Compiler.scope_declares_alias(Compiler c, String name) {
  List row = c.sym.current_binding($(name));
  if (row && c.fact(%(alias $row))) return 1;
  return _same_scope(c, _entry(c, name, NULL));
}

// uses

/** Returns the expression that the identifier at the cursor stands for when
    it names a visible alias, or NULL. A declaration in a scope inside the
    alias's scope shadows it. The expression keeps its bindings where a
    later declaration hides one of their names.
*/
List Compiler.alias_expression(Compiler c) {
  if (c.peek(0) != <ident>) return NULL;
  Map table = _table(c);
  if (!table && !c.sym.has_aliases()) return NULL;
  String name = c.token.text;
  List symbol = $(name);
  int scope = c.sym.declaring_scope(symbol);
  Var key;
  List entry = _entry(c, name, key), expression = NULL;
  if (entry) expression = _visible(c, table, key, entry, scope);
  if (!expression && c.sym.has_aliases() &&
      scope >= c.sym.base_scope_count())
    expression = c.fact(%(alias $(c.sym.lookup(symbol, NULL))));
  if (expression && !c.macro_holes) _reveal_bindings(c, expression);
  return expression;
}

static void _reveal_bindings(Compiler c, List syntax) {
  if (syntax ~= %(expr ? $($source_identifier_content(%(?binding))))) {
    c.reveal_binding(binding);
    return;
  }
  foreach (Var child in syntax)
    if (child is <list>) _reveal_bindings(c, child);
}

/* An imported entry's identifiers bind in the unit's global scope. The
   thawed entry replaces the frozen one in the current table without a
   copy: thawing changes no meaning, so a body that restores an outer table
   holding the frozen entry only thaws it again. */
static List _visible(Compiler c, Map table, Var key, List entry, int scope) {
  if (entry ~= %(imported ?frozen *shadowed)) {
    List expression = _rebind_globals(c, c.thaw_declaration_syntax(frozen));
    entry = %(declared $(c.sym.base_scope_count()) 0 $expression @shadowed);
    table[key] = entry;
  }
  if (entry ~= %(declared ?(int depth) ? ?expression *) && depth > scope)
    return expression;
  return NULL;
}
