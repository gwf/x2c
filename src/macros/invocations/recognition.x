/*  recognition.x -- macro invocation recognition */

module typedef struct MacroPos {
  Symbol kind, const char *description, int semicolon;
} MacroPos;

static const SymbolSet alias_kinds =
  %<<expression block-item field enumerator map-entry unit decorator>>;

static const SymbolSet macro_positions =
  %<<unit block field enumerator map-entry statement expression>>;

static const MacroPos macro_position_info[] = {
  { <unit>,       "file scope",    1 },
  { <block-item>, "block scope",   1 },
  { <field>,      "field scope",   1 },
  { <enumerator>, "an enum body",  0 },
  { <map-entry>,  "a map literal", 0 },
  { <block-item>, "block scope",   1 },
  { <expression>, "an expression", 0 }
};

// definition forms and keyword aliases

/** Publishes a canonical `macrodef` in source order and returns `node`.
    A later definition with the same name affects only later invocations.
*/
List Compiler.publish_macro_definition_node(Compiler c, List node) {
  c.macros[node.assoc(<name>)] = node;
  if (c.shallow && !c.macro_holes &&
      !node.assoc(<static>).equal(1) && !node.assoc(<local>).int())
    _record_compile_time_effect(
      c, %(compile-time macrodef $(c.freeze_declaration_syntax(node))),
      c.token);
  return node;
}

/** Installs included compile-time definitions in their source order.
    Keyword aliases retain the definition visible when their source declared
    them, even if a later macro definition uses the same name.
*/
void Compiler.install_compile_time_effects(Compiler c, List rows) {
  foreach (List row in rows) match (row) {
    case %(compile-time effects *effects):
      c.install_compile_time_effects(effects);
    case %(compile-time macrodef ?definition): {
      Var name = c.thaw_declaration_syntax(definition.list().assoc(<name>));
      c.macros[name] = %(imported-macro $definition);
    }
    case %(compile-time keyword ?alias ?definition): {
      if (!c.kw_aliases) c.kw_aliases = {};
      c.kw_aliases[alias] = %(imported-macro $definition);
    }
    case %(compile-time alias ?(String name) ?expression):
      _install_imported_alias(c, name, expression);
    case %(compile-time unalias ?(String name)):
      _remove_imported_alias(c, name);
    case %(compile-time rewrite *): _install_rewrite(c, row);
    case %(project-meta *): c.install_project_meta_effect(row);
  }
}

/** Returns whether the current tokens have macro-definition introducer form.
    This query does not consume tokens.
*/
int Compiler.macro_form_is_definition(Compiler c) {
  Token token = c.token;
  int offset = c.peek(0) == <static>;
  if (offset) token = Token.skip_trivia(token + 1);
  if (c.peek(offset) != <ident> || token.text != "macro") return 0;
  if (c.peek(offset + 1) == <$>) return 1;
  return c.peek(offset + 1) == <ident> &&
    (c.peek(offset + 2) == <$> ||
     (c.peek(offset + 2) == <ident> && c.peek(offset + 3) == <$>));
}

/** Returns whether the current tokens begin a local macro definition.
    This query does not consume tokens.
*/
int Compiler.local_macro_form_is_definition(Compiler c) {
  /* The `<(>` literal keeps this body braced: the API reference generator
     reads it as an unbalanced parenthesis and drops the rest of the file. */
  return c.at_word("macro") && c.peek(1) == <ident> &&
         c.peek(2) == <ident> && c.peek(3) == <(>;
}

/** Returns whether the current tokens begin a `keyword NAME $macro` alias.
    This query does not consume tokens.
*/
int Compiler.keyword_form_is_definition(Compiler c) {
  Token token = c.token;
  int offset = c.peek(0) == <static>;
  if (offset) token = Token.skip_trivia(token + 1);
  return c.peek(offset) == <ident> && token.text == "keyword" &&
         c.peek(offset + 2) == <$>;
}

/** Parses and installs one source-local `keyword` alias.
    The named macro must already be visible; the alias captures that definition
    and consumes its terminating semicolon. Returns the alias.
*/
Atom Compiler.parse_keyword_definition(Compiler c) {
  Token declaration = c.token;
  int storage = c.test(<static>) || c.source_private;
  c.expect(<ident>);
  if (c.peek(0) != <ident>)
    $fail.macros_keyword_name(c, c.token);
  Atom alias = Atom.intern(c.token.text);
  c.next();
  if (_fixed_alias(c, alias))
    $fail.macros_keyword_builtin(c, declaration);
  Token reference = c.token;
  List definition = _lookup(c, _name(c), reference);
  Symbol kind = definition.assoc(<kind>);
  if (!(kind in alias_kinds)) {
    String spelling = _kind_spelling(kind);
    $fail.macros_keyword_internal(
      c, declaration, spelling, _definition_note(definition));
  }
  c.expect(<;>);
  c.kw_aliases[alias] = definition;
  if (!storage)
    _record_compile_time_effect(
      c, %(compile-time keyword $alias
        $(c.freeze_declaration_syntax(definition))), declaration);
  return alias;
}

/* invocation recognition

   At each syntax position the parser asks whether the tokens start an
   invocation it should claim. Recognition consumes nothing; a claimed
   invocation's name is consumed once its definition is known. */

/** Returns whether the parser claims the macro invocation at the cursor for
    `position`. A bare keyword alias is claimed only where its result fits.
    This query does not consume tokens.
*/
int Compiler.macro_starts_target_at(Compiler c, Symbol position) =>
  _claims(c, _peek_invocation(c, position), position);

// shallow collection

/** Returns how collection treats the macro invocation at the cursor.
    `<required>` covers every file-scope `Unit` macro, declaration-unit macro,
    named-type decorator, and local `Unit` macro whose template contains
    protocol or adoption rows. `<tried>` covers Unit decorators and other
    local `Unit` macros. Other invocations return zero.
*/
Symbol Compiler.macro_invocation_collection(Compiler c) {
  List definition = _peek_invocation(c, <unit>);
  if (!definition) return 0;
  if (definition.assoc(<kind>) == <decl-unit> ||
      definition.assoc(<target>) == <named-type>) return <required>;
  if (definition.assoc(<target>) == <unit>) return <tried>;
  if (definition.assoc(<kind>) != <unit>) return 0;
  if (!definition.assoc(<local>).int()) return <required>;
  List template = definition.assoc(<template>), bindings;
  Var matched;
  if (template.try_search(%(!or (protocol *) (adopt *)), matched, bindings))
    return <required>;
  return <tried>;
}

/** Consumes a NamedType target already projected by owning-source collection.
    CPP scanning does not produce the declaration or parse its fields again.
*/
int Compiler.skip_named_type_declaration(Compiler c) {
  List definition = _peek_invocation(c, <unit>);
  if (!definition || definition.assoc(<target>) != <named-type>) return 0;
  c.skip_macro_invocation();
  _x2c_skip_shallow_expression(c, 0);
  c.expect(<;>);
  return 1;
}

/** Consumes a macro invocation name and its balanced argument list.
    The invocation terminator or following decorator target remains current.
*/
void Compiler.skip_macro_invocation(Compiler c) {
  int bare = _bare(c.token, _peek_invocation(c, <unit>));
  String spelling;
  if (c.peek(0) == <$>) c.token = _scan_name(c, spelling);
  else c.next();
  if (!bare && c.peek(0) == <(>) c.token = c.token.after_group();
}

/** Reports whether the macro invocation at the cursor produces file-scope
    syntax, directly or through the target it decorates. A script unit keeps
    such an invocation at file scope. This query does not consume tokens.
*/
int Compiler.macro_targets_unit(Compiler c) {
  List definition = _peek_invocation(c, <unit>);
  if (!definition) return 0;
  Symbol kind = _result_kind(definition);
  return kind == <unit> || kind == <decl-unit>;
}

// macro invocation recognition

/* Records a public source effect where its completed definition stands. */
module void _record_compile_time_effect(Compiler c, List row, Token start) {
  if (!c.shallow || c.source_private || c.macro_holes ||
      !c.sym.at_file_scope() || !c.filename) return;
  String source = Compiler.portable_path(Path.absolute(c.filename));
  List key = %("source-node" (compile-time $source $(start.pos)));
  List previous = c.sym.get(key);
  if (previous) row = %(compile-time effects $previous $row);
  c.sym.set(key, row);
}

/* Only the built-in sources define `with` or replace a built-in alias. */
static int _fixed_alias(Compiler c, Atom alias) {
  Var existing;
  return !c.builtin_defs &&
    (alias == <with> ||
     (_try_macro(c, c.kw_aliases, alias, existing) &&
      existing.list().assoc(<builtin>).int()));
}

module Atom _name(Compiler c) {
  String spelling;
  Token end = _scan_name(c, spelling);
  if (!spelling)
    $fail.macros_macro_name(c, end);
  c.token = end;
  return Atom.intern(spelling);
}

/* Scans the dotted name after the current `$` without consuming tokens.
   A component after a dot may be a keyword, as in `$error.arg.void`.
   Returns the token after the name, or the token where a name component is
   missing with `spelling` set to NULL. */
module Token _scan_name(Compiler c, String &spelling) {
  Token token = c.token, String name = NULL;
  do {
    token = Token.skip_trivia(token + 1);
    if (token.type != <ident> &&
        !(name && scan_keyword_type(token.text, token.text.len()))) {
      name = NULL;
      break;
    }
    name = name ? %"$name.$(token.text)" : token.text;
    token = Token.skip_trivia(token + 1);
  } while (token.type == <.>);
  spelling = name;
  return token;
}

module List _lookup(Compiler c, Atom name, Token invocation) {
  Var stored;
  String spelling = name.str();
  if (!_try_macro(c, c.macros, name, stored))
    $fail.macros_macro_unbound(c, invocation, spelling);
  return stored;
}

/* Includes publish names immediately. Decode a template into this unit's
   bindings only when it is used, keeping the result in the same name map. */
module int _try_macro(Compiler c, Map definitions, Atom name, Var &stored) {
  if (!definitions.try_get(name, stored)) return 0;
  if (stored ~= %(imported-macro ?definition)) {
    stored = _rebind_imported(c, c.thaw_declaration_syntax(definition));
    c.sym.put(definitions, name, stored);
  }
  return 1;
}

/* Cached templates retain global references across symbol-table resets.
   Bind those names in the current global scope without replaying imports. */
module Var _rebind_imported(Compiler c, Var stored) {
  if (stored is not <list>) return stored;
  List definition = stored;
  if (definition.car() != <macrodef>) return definition;
  return _rebind_globals(c, definition);
}

/* Binds each identifier of cached syntax in the current global scope. */
module List _rebind_globals(Compiler c, List syntax) {
  Map replacements = {};
  _reference_bindings(c, syntax, replacements);
  return replacements.len() ? _replace_bindings(syntax, replacements) : syntax;
}

static void _reference_bindings(Compiler c, List syntax, Map replacements) {
  if (syntax ~= %(expr ? (ident ?binding))) {
    String spelling = NULL;
    if (Ast.try_binding(binding, NULL, spelling))
      replacements[binding] = c.sym.reference_global($(spelling));
    return;
  }
  foreach (Var child in syntax)
    if (child is <list>) _reference_bindings(c, child, replacements);
}

/* An invocation is claimed where its result fits. A statement or map entry
   that does not fit parses as an expression. Elsewhere a `$` name, or an
   identifier with arguments, is claimed so that its target parser reports
   the position diagnostic; a local expression macro at block scope and an
   evaluated `$(...)` or `${...}` collection remain expressions. */
static int _claims(Compiler c, List definition, Symbol position) {
  Symbol kind = definition ? _result_kind(definition) : 0;
  if (kind == _position(position).kind) return 1;
  if (definition && c.peek(0) == <auto> && position == <unit>) return 1;
  if (position == <statement> || position == <map-entry>) return 0;
  if (!definition) {
    if (c.peek(0) == <$> && (position == <block> || c.macro_holes) &&
        _meta_callee(c).is_function())
      return 0;
    Symbol next = (c.token + 1).type;
    return c.peek(0) == <$> && next != <(> && next != <"{">;
  }
  return !_bare(c.token, definition) &&
    (position != <block> || kind != <expression> ||
     !definition.assoc(<local>).int());
}

/* Returns the type of the identifier a `$` meta call reads, as in
   `$Code.type(value)`, when that identifier spans the whole `$` name.
   Consumes no tokens. A missing package member is left to the invocation
   diagnostic. */
static Type _meta_callee(Compiler c) {
  Token start = c.token;
  String name;
  Token end = _scan_name(c, name);
  c.next();
  String member = c.package_alias_spelling();
  List callee = name && (!member || c.sym.get_exact($(member)))
              ? c.parse_complex_identifier() : NULL;
  Type type = callee && c.token == end ? c.sym.get(callee) : NULL;
  c.token = start;
  return type;
}

module const MacroPos *_position(Symbol position) =>
  &macro_position_info[macro_positions.index(position)];

module Symbol _result_kind(List definition) {
  Symbol kind = definition.assoc(<kind>);
  if (kind != <decorator>) return kind;
  Symbol target = definition.assoc(<target>);
  if (target == <function> || target == <unit> || target == <named-type>)
    return <unit>;
  if (target == <block>) return <block-item>;
  if (target == <expr>) return <expression>;
  return target;
}

/* Returns the definition invoked at the cursor without consuming tokens, or
   NULL. A `$` name invokes its visible definition. An identifier invokes the
   innermost local macro of that name, or else its keyword alias, when an
   argument list follows or the invocation is bare. */
module List _peek_invocation(Compiler c, Symbol position) {
  Var stored;
  if (c.peek(0) == <auto>) {
    if (!c.auto_region_form(position)) return NULL;
    String region = c.peek(1) == <(> ? "x2c.auto.destination"
                                     : "x2c.auto.region";
    return _lookup(c, Atom.intern(region), c.token);
  }
  /* `with` is not a keyword alias: one would claim `with(41)` in an
     expression, where the book keeps `with` an ordinary name. Only a
     statement begins the built-in decorator. */
  if (c.at_word("with") && c.peek(1) == <(> &&
      (position == <statement> || position == <block>))
    return _lookup(c, Atom.intern("x2c.with"), c.token);
  if (c.peek(0) == <$> || c.peek(0) == <@>) {
    String spelling;
    _scan_name(c, spelling);
    if (!spelling ||
        !_try_macro(c, c.macros, Atom.intern(spelling), stored))
      return NULL;
    return stored;
  }
  if (c.peek(0) != <ident>) return NULL;
  Atom name = Atom.intern(c.token.text);
  List definition = c.sym.has_local_macros()
                  ? c.sym.lookup_macro(name) : NULL;
  if (!definition && _try_macro(c, c.kw_aliases, name, stored))
    definition = stored;
  return definition && (c.peek(1) == <(> || _bare(c.token, definition))
       ? definition : NULL;
}

/* An identifier invoking a decorator without explicit parameters has no
   argument list. */
module int _bare(Token invocation, List definition) =>
  invocation.type != <$> && invocation.type != <@> &&
  definition.assoc(<kind>) == <decorator> &&
  !definition.assoc(<parameters>).list();

/* Consumes the name of an invocation claimed at `position` and returns its
   definition, or returns NULL without consuming tokens. A `$` name that is
   neither visible nor followed by arguments is a replacement variable
   missing from a template. */
module List _take_invocation(Compiler c, Symbol position) {
  List definition = _peek_invocation(c, position);
  if (!_claims(c, definition, position)) return NULL;
  if (c.peek(0) != <$> && c.peek(0) != <@>) {
    c.next();
    return definition;
  }
  Token invocation = c.token;
  Atom name = _name(c);
  Var existing;
  if (c.macro_holes && c.peek(0) != <(> &&
      !_try_macro(c, c.macros, name, existing))
    _unbound(c, name.str(), invocation);
  return _lookup(c, name, invocation);
}
