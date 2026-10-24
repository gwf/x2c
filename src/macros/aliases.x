/*  aliases.x -- lexical expression aliases

    `alias expression as name` names a parsed expression until the name's
    scope ends. Each use of the name in expression position stands for a
    parenthesized copy of the expression, so an unused alias evaluates
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
    it at the same Sym depth.
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

static macro Stmt $fail.macros_alias_governed(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "alias declaration cannot be the body of a statement",
    $site, %("give the alias a braced body"));

// recognition

/** Reports whether the cursor begins an alias: the word `alias`, or at
    file scope `static alias`, then an expression followed by `as` or a
    braced body. `alias` stays an ordinary name where it continues an
    operand, as in `alias = value;`, and where it names a type that no
    `as` follows. This query does not consume tokens.
*/
int Compiler.alias_form_starts(Compiler c) {
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

/** Parses an alias in a function body or a template. The semicolon form
    defines its name in the current scope and returns `(seq)`; it requires
    block position, which `block` reports. The braced form returns its
    block, with the name defined in a scope around it.
*/
List Compiler.parse_alias_statement(Compiler c, int block) {
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
  if (%(${head.name}) in c.sym.current_symbols())
    $fail.parse_decl_bound(c, head.start, head.name);
  c.sym.define_alias(head.name, head.expression);
}

/** Parses an alias at file scope. A semicolon alias returns NULL; its name
    stays visible to the rest of the unit and, unless it is `static`, to the
    files that include this one. A braced alias returns `(seq ...)` of the
    top-level forms it wraps, which keep their file-scope placement while
    the name ends at the closing brace. Collection, with `skip_body`, reads
    the wrapped forms as it reads any other. Inside a template the name is
    the template's own, as at block scope.
*/
List Compiler.parse_alias_declaration(Compiler c, int skip_body) {
  if (!c.sym.at_file_scope()) return _template_declaration(c, skip_body);
  AliasHead head = _head(c);
  if (c.test(<;>)) {
    _declare(c, head);
    return NULL;
  }
  Map mark = c.enter_alias_body();
  defer c.leave_alias_body(mark);
  _declare(c, head);
  c.next();
  return _wrapped_forms(c, skip_body);
}

static List _template_declaration(Compiler c, int skip_body) {
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

/* Directives between the forms stay among them, and an include among them
   delivers its definitions there. */
static List _wrapped_forms(Compiler c, int skip_body) {
  Array forms = [];
  loop {
    List directives = c.leading_preproc();
    if (!skip_body && c.included_effects) c.install_included_effects();
    foreach (List directive in directives) forms.push(directive);
    if (c.peek(0) == <"}"> || c.peek(0) == <eof>) break;
    List form = skip_body ? NULL : c.replay_declaration_source();
    if (!form) form = c.parse_top_level_mode(skip_body);
    if (form && form.car() == <seq>)
      foreach (List item in form.cdr()) forms.push(item);
    else if (form) forms.push(form);
  }
  c.expect(<"}">);
  return %(seq @{forms.list_free()});
}

/** Parses an alias among the members of an aggregate or enum body, where
    `position` is `<field>` or `<enumerator>` and `context` is the
    aggregate type. Its name ends with the body. A braced alias returns
    `(seq ...)` of the members it wraps; a semicolon alias returns `(seq)`.
*/
List Compiler.parse_alias_member(
  Compiler c, Symbol position, List context) {
  AliasHead head = _head(c);
  if (c.test(<;>)) {
    _declare(c, head);
    return %(seq);
  }
  Map mark = c.enter_alias_body();
  defer c.leave_alias_body(mark);
  _declare(c, head);
  c.next();
  List members = position == <enumerator> ? c.parse_enumerators(context)
               : c.peek(0) == <"}"> ? NULL : c.parse_fields(context);
  c.expect(<"}">);
  return %(seq @members);
}

/* An entry is `(declared depth level file expression)`: the Sym scope
   count and body level at its declaration, and for a `static` alias of a
   module file, the prefix of that file. Another alias of the same name
   at the same depth and level is the same scope's. A semicolon alias at
   file scope also conflicts with a file-scope declaration of its name,
   and records its compile-time effect for including files. */
static void _declare(Compiler c, AliasHead &head) {
  int depth = c.sym.scope_count(), level = c.alias_level;
  match (_entry(c, head.name))
    case %(declared ?(int prior_depth) ?(int prior_level) *):
      if (prior_depth == depth && prior_level == level)
        $fail.parse_decl_bound(c, head.start, head.name);
  int file_scope = !level && c.sym.at_file_scope();
  if (file_scope && c.sym.get_exact(%(${head.name})))
    $fail.parse_decl_bound(c, head.start, head.name);
  String file = head.storage ? c.file_prefix() : NULL;
  _install(c, head.name,
    %(declared $depth $level ${file ? file : ""} ${head.expression}));
  if (file_scope && !head.storage)
    _record_compile_time_effect(
      c, %(compile-time alias ${head.name}
        ${c.freeze_declaration_syntax(head.expression)}), head.start);
}

/* Entries live in one Map under `<alias>`, which each declaration
   replaces with a copy, so a body restores its outer entries by restoring
   the Map it started with. */
static void _install(Compiler c, String name, List entry) {
  Map table = _table(c);
  table = table ? table.copy() : {};
  table[name] = entry;
  c.sym.put(c.macros, <alias>, table);
}

static Map _table(Compiler c) {
  Var stored;
  return c.macros.try_get(<alias>, stored) ? stored : NULL;
}

static List _entry(Compiler c, String name) {
  Map table = _table(c);
  Var entry;
  return table && table.try_get(name, entry) ? entry : NULL;
}

/** Starts a declaration body whose aliases end at its closing brace, and
    returns the alias state that `Compiler.leave_alias_body` restores. */
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
   is thawed when the name is first used. */
module void _install_imported_alias(Compiler c, String name, List frozen) =>
  _install(c, name, %(imported $frozen));

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
  List key = %($name);
  int scope = c.sym.declaring_scope(key);
  Var entry;
  List expression = NULL;
  if (table && table.try_get(name, entry))
    expression = _visible(c, table, name, entry, scope);
  if (!expression && c.sym.has_aliases() &&
      scope >= c.sym.base_scope_count())
    expression = c.fact(%(alias ${c.sym.lookup(key, NULL)}));
  if (expression && !c.macro_holes) _reveal_bindings(c, expression);
  return expression;
}

static void _reveal_bindings(Compiler c, List syntax) {
  match (syntax)
    case %(expr ? ${$source_identifier_content(%(?binding))}): {
      c.reveal_binding(binding);
      return;
    }
  foreach (Var child in syntax)
    if (child is <list>) _reveal_bindings(c, child);
}

/* An imported entry's identifiers bind in the unit's global scope. */
static List _visible(
  Compiler c, Map table, String name, List entry, int scope) {
  match (entry) case %(imported ?frozen): {
    List expression = _rebind_globals(c, c.thaw_declaration_syntax(frozen));
    entry = %(declared ${c.sym.base_scope_count()} 0 "" $expression);
    table[name] = entry;
  }
  match (entry)
    case %(declared ?(int depth) ? ?(String file) ?expression):
      if (depth > scope && (!file.len() || file == c.file_prefix()))
        return expression;
  return NULL;
}
