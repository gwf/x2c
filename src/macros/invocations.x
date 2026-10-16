/*  invocations.x -- macro recognition and argument capture */

static typedef struct MacroPos {
  Symbol kind, const char *description, int semicolon;
} MacroPos;

/* decorators

   A decorator application parses the decorator's arguments and then its
   target. Parsing the target can publish symbols before the replacement is
   known, so one semantic transaction stages the target and the expansion
   and a rejection rolls both back. */

/* One decorator application. A Block decorator standing before a
   file-scope function decorates that function's body, so one spelling
   covers a statement and a whole function; `function` holds the function
   then. */
static typedef struct Decoration {
  Compiler c, List definition, function, Token invocation, start;
  Symbol position, Symbol kind, int open;
} Decoration;

// definition forms and keyword aliases

/** Publishes a canonical `macrodef` in source order and returns `node`.
    A later definition with the same name affects only later invocations.
*/
List Compiler.publish_macro_definition_node(Compiler c, List node) {
  c.macros[node.assoc(<name>)] = node;
  if (c.shallow && !c.macro_holes &&
      !node.assoc(<static>).equal(1) && !node.assoc(<local>).int())
    c.record_compile_time_effect(
      %(compile-time macrodef ${c.freeze_declaration_syntax(node)}), c.token);
  return node;
}

/** Records a public source effect where its completed definition stands. */
void Compiler.record_compile_time_effect(
  Compiler c, List row, Token start) {
  if (!c.shallow || c.source_private || c.macro_holes ||
      !c.sym.at_file_scope() ||
      c.builtin_defs || !c.filename ||
      c.filename.startswith("<builtin:")) return;
  String source = Compiler.portable_path(Path.absolute(c.filename));
  List key = %("source-node" (compile-time $source ${start.pos}));
  List previous = c.sym.get(key);
  if (previous) row = %(compile-time effects $previous $row);
  c.sym.set(key, row);
}

/** Installs included compile-time definitions in their source order.
    Keyword aliases retain the definition visible when their source declared
    them, even if a later macro definition uses the same name.
*/
void Compiler.install_compile_time_effects(Compiler c, List rows) {
  foreach (List row, rows) match (row) {
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
    case %(compile-time rewrite *): _install_rewrite(c, row);
    case %(compile-time lisp ?form (source ?path ?site)): {
      Token token = c.thaw_declaration_syntax(site);
      String file = Compiler.absolute_home_path(path), text = NULL;
      c.read_source(file, text);
      $let(c.filename, file)
      $let(c.text, text)
      $let(c.line_markers, NULL) {
        if (c.shallow) c.queue_declaration_effect(form, token, NULL);
        else c.evaluate_declaration_effect(form, token);
      }
    }
    case %(compile-time import ?path (source ?source ?site)): {
      Token token = c.thaw_declaration_syntax(site);
      String file = Compiler.absolute_home_path(source), text = NULL;
      c.read_source(file, text);
      $let(c.filename, file)
      $let(c.text, text)
      $let(c.line_markers, NULL)
        _import(c, Compiler.absolute_home_path(path), token);
    }
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
    c.record_compile_time_effect(
      %(compile-time keyword $alias
        ${c.freeze_declaration_syntax(definition)}), declaration);
  return alias;
}

/* Only the built-in sources define `with` or replace a built-in alias. */
static int _fixed_alias(Compiler c, Atom alias) {
  Var existing;
  return !c.builtin_defs &&
    (alias == <with> ||
     (_try_macro(c, c.kw_aliases, alias, existing) &&
      existing.list().assoc(<builtin>).int()));
}

static const SymbolSet alias_kinds =
  %<<expression block-item field enumerator map-entry unit decorator>>;

/* Parses one keyword alias of `c`'s source into `aliases`. */
module void _record_alias(Compiler c, Map aliases) {
  Atom alias = c.parse_keyword_definition();
  aliases[alias] = c.kw_aliases[alias];
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
  _claims(c, _peek_invocation(c), position);

/* An invocation is claimed where its result fits. A statement or map entry
   that does not fit parses as an expression. Elsewhere a `$` name, or an
   identifier with arguments, is claimed so that its target parser reports
   the position diagnostic; a local expression macro at block scope remains
   an expression statement. */
static int _claims(Compiler c, List definition, Symbol position) {
  Symbol kind = definition ? _result_kind(definition) : 0;
  if (kind == _position(position).kind) return 1;
  if (position == <statement> || position == <map-entry>) return 0;
  if (!definition) {
    if (c.peek(0) == <$> && (position == <block> || c.macro_holes) &&
        _meta_callee(c).is_function())
      return 0;
    return c.peek(0) == <$>;
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
  List callee = name && (!member || c.sym.get_exact(%($member)))
              ? c.parse_complex_identifier() : NULL;
  Type type = callee && c.token == end ? c.sym.get(callee) : NULL;
  c.token = start;
  return type;
}

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

static const MacroPos *_position(Symbol position) =>
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
module List _peek_invocation(Compiler c) {
  Var stored;
  if (c.peek(0) == <$> || c.peek(0) == <@>) {
    String spelling;
    _scan_name(c, spelling);
    if (!spelling ||
        !_try_definition(c, Atom.intern(spelling), !c.shallow, stored))
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
    name = name ? %"$name.${token.text}" : token.text;
    token = Token.skip_trivia(token + 1);
  } while (token.type == <.>);
  spelling = name;
  return token;
}

/* An identifier invoking a decorator without explicit parameters has no
   argument list. */
static int _bare(Token invocation, List definition) =>
  invocation.type != <$> && invocation.type != <@> &&
  definition.assoc(<kind>) == <decorator> &&
  !definition.assoc(<parameters>).list();

/* Consumes the name of an invocation claimed at `position` and returns its
   definition, or returns NULL without consuming tokens. A `$` name that is
   neither visible nor followed by arguments is a replacement variable
   missing from a template. */
static List _take_invocation(Compiler c, Symbol position) {
  List definition = _peek_invocation(c);
  if (!_claims(c, definition, position)) return NULL;
  if (c.peek(0) != <$> && c.peek(0) != <@>) {
    c.next();
    return definition;
  }
  Token invocation = c.token;
  Atom name = _name(c);
  Var existing;
  if (c.macro_holes && c.peek(0) != <(> &&
      !_try_definition(c, name, 1, existing))
    _unbound(c, name.str(), invocation);
  return _lookup(c, name, invocation);
}

module Atom _name(Compiler c) {
  String spelling;
  Token end = _scan_name(c, spelling);
  if (!spelling)
    $fail.macros_macro_name(c, end);
  c.token = end;
  return Atom.intern(spelling);
}

module List _lookup(Compiler c, Atom name, Token invocation) {
  Var stored;
  String spelling = name.str();
  if (!_try_definition(c, name, 1, stored))
    $fail.macros_macro_unbound(c, invocation, spelling);
  return stored;
}

/* With `install_lisp`, a `lisp.` name records the Lisp binding macros as a
   dependency and installs them when the name is not yet defined. */
module int _try_definition(
  Compiler c, Atom name, int install_lisp, Var &stored) {
  int found = _try_macro(c, c.macros, name, stored);
  String spelling = name.str();
  if (!install_lisp || !spelling.startswith("lisp.")) return found;
  _use_lisp_bindings(c, !found);
  return found || _try_macro(c, c.macros, name, stored);
}

/* Includes publish names immediately. Decode a template into this unit's
   bindings only when it is used, keeping the result in the same name map. */
static int _try_macro(
  Compiler c, Map definitions, Atom name, Var &stored) {
  if (!definitions.try_get(name, stored)) return 0;
  match (stored) case %(imported-macro ?definition): {
    stored = _rebind_imported(c, c.thaw_declaration_syntax(definition));
    c.sym.put(definitions, name, stored);
  }
  return 1;
}

// shallow collection

/** Returns how collection treats the macro invocation at the cursor.
    `<required>` covers every file-scope `Unit` macro, declaration-unit macro,
    named-type decorator, and local `Unit` macro whose template contains
    protocol or adoption rows. `<tried>` covers Unit decorators and other
    local `Unit` macros. Other invocations return zero.
*/
Symbol Compiler.macro_invocation_collection(Compiler c) =>
  _collection(_peek_invocation(c));

static Symbol _collection(List definition) {
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

/** Consumes a macro invocation name and its balanced argument list.
    The invocation terminator or following decorator target remains current.
*/
void Compiler.skip_macro_invocation(Compiler c) {
  int bare = _bare(c.token, _peek_invocation(c));
  String spelling;
  if (c.peek(0) == <$>) c.token = _scan_name(c, spelling);
  else c.next();
  if (!bare && c.peek(0) == <(>) c.token = c.token.after_group();
}

/** Consumes a NamedType target already projected by owning-source collection.
    CPP scanning does not produce the declaration or parse its fields again.
*/
int Compiler.skip_named_type_declaration(Compiler c) {
  List definition = _peek_invocation(c);
  if (!definition || definition.assoc(<target>) != <named-type>) return 0;
  c.skip_macro_invocation();
  _x2c_skip_shallow_expression(c, 0);
  c.expect(<;>);
  return 1;
}

/** Reports whether the macro invocation at the cursor produces file-scope
    syntax, directly or through the target it decorates. A script unit keeps
    such an invocation at file scope. This query does not consume tokens.
*/
int Compiler.macro_targets_unit(Compiler c) {
  List definition = _peek_invocation(c);
  if (!definition) return 0;
  Symbol kind = _result_kind(definition);
  return kind == <unit> || kind == <decl-unit>;
}

/* invocation arguments

   Each parameter hole captures its arguments into one capture row, and a
   captured argument records the source span it was parsed from. */

static List _invocation_arguments(
  Compiler c, List definition, Token invocation) {
  if (_bare(invocation, definition)) return %(args);
  Array arguments = [];
  // The first Param hole opens one scope for the rest of the arguments.
  int parameter_scope = 0;
  defer { if (parameter_scope) c.sym.pop_scope(); }
  c.expect(<(>);
  List descriptors = definition.assoc(<parameters>);
  for (List nodes = descriptors; nodes; nodes = nodes.cdr()) {
    List hole = nodes.car();
    Symbol kind = hole.assoc(<kind>);
    if (kind == <param> && !parameter_scope) {
      c.sym.push_new_scope();
      parameter_scope = 1;
    }
    arguments.push(_argument_row(c, hole, kind));
    if (nodes.cdr() && c.peek(0) != <)>) _argument_separator(c, kind);
  }
  if (c.peek(0) != <)>) {
    if (c.peek(0) == <,>) c.next();
    $fail.macros_macro_extra_args(c, c.token);
  }
  c.expect(<)>);
  return %(args @{arguments.list_free()});
}

/* The arguments one hole captures: one, or a comma-separated sequence. A
   MatchRow hole also takes the directives around its rows. */
static List _argument_row(Compiler c, List hole, Symbol kind) {
  int sequence = hole.assoc(<sequence>);
  Array captured = [];
  if (c.peek(0) == <)> && !sequence)
    $fail.macros_macro_missing_args(c, c.token);
  if (c.peek(0) != <)>) loop {
    _row_directives(c, kind, captured);
    Token first = c.token;
    Var argument = _parse_argument(c, kind);
    if (kind != <name>)
      argument = _capture_source(c, argument, first, c.token);
    captured.push(argument);
    if (!sequence || !c.test(<,>)) break;
  }
  _row_directives(c, kind, captured);
  return _capture_row_project(c, hole, captured.list_free(), 0);
}

static void _row_directives(Compiler c, Symbol kind, Array captured) {
  if (kind == <match-row> && c.token != c.directives_taken)
    foreach (List directive, c.leading_preproc()) captured.push(directive);
}

/* `in` may separate a declaration from what follows, as in
   `foreach (String line in lines)`. Before a literal it scans as a name,
   which cannot follow a declaration either. */
static void _argument_separator(Compiler c, Symbol kind) {
  if (kind == <decl> && (c.peek(0) == <in> || c.at_word("in"))) c.next();
  else c.expect(<,>);
}

static Var _parse_argument(Compiler c, Symbol kind) {
  // Captures retain complete syntax even while collection skips other bodies.
  $let(c.shallow, 0) {
    if (!kind) return c.parse_assignment();
    switch (kind) {
      case <expr>:       return c.parse_assignment();
      case <type>:       return c.parse_type_name();
      case <named-type>: return c.parse_named_type();
      case <decl>:       return c.parse_declaration_argument();
      case <decl-row>:   return c.parse_declarator_argument();
      case <function>:   return c.parse_function_definition();
      case <param>:      return c.parse_parameter();
      case <block>:      return c.parse_block_item();
      case <field>:      return c.parse_field(%(struct ()));
      case <enumerator>: return c.parse_enumerator(c.aggregate_type);
      case <map-entry>:  return c.parse_map_entry();
      case <match-row>:  return c.parse_match_row_argument();
      case <unit>:       return c.parse_top_level();
      case <name>:       return _name_argument(c);
      case <literal>:    return _literal_argument(c);
    }
    $fail.macros_argument_contract(c, c.token);
  }
}

/* A caller's name is a spelling, resolved where the expansion places it.
   A name a template writes is private to each expansion: a nested
   declaration made from it is that expansion's, and a reference that no
   such declaration reaches reads its spelling where the expansion lands. */
static Var _name_argument(Compiler c) {
  if (c.macro_holes && c.peek(0) == <$>) return _parse_hole(c, <name>);
  if (c.peek(0) != <ident>)
    $fail.macros_name_identifier(c, c.token);
  String spelling = c.token.text;
  c.next();
  if (!c.macro_holes) return spelling;
  List visible = c.sym.lookup(%($spelling), NULL);
  if (visible && visible in c.macro_definition_locals()) return visible;
  List local = c.macro_introduced_name(spelling);
  c.bind_template_local(local, NULL, NULL);
  c.macro_definition_locals()[%(name-argument $spelling)] = local;
  return local;
}

static Var _literal_argument(Compiler c) {
  if (c.macro_holes && c.peek(0) == <$>) return c.parse_assignment();
  return c.parse_atomic_literal();
}

static Var _capture_source(
  Compiler c, Var syntax, Token first, Token after) {
  if (c.macro_holes || syntax is not <list> ||
      syntax.is_nil() || !first) return syntax;
  Token last = _previous_source_token(c, after);
  if (!last || last < first) return syntax;
  int end = last.pos + last.len;
  String file = c.source_path(c.filename ? c.filename : "<stdin>");
  List source = %(source $file ${first.pos} $end);
  return %(src $source $syntax);
}

static Token _previous_source_token(Compiler c, Token after) {
  Token first = (void *) c.tokenizer.tokens;
  if (!after || after <= first) return NULL;
  Token token = after - 1;
  while (token > first &&
         (token.type == <space> || token.type == <comment> ||
          token.type == <preproc>)) token--;
  return token;
}

/* A Block decorator's Name arguments are referenced in the block's scope,
   which opens before the arguments are read. */
static void _bind_name_arguments(
  Compiler c, List definition, List arguments) {
  List parameters = definition.assoc(<parameters>);
  List captures = arguments.cdr();
  while (parameters) {
    List parameter = parameters.car();
    if (parameter.assoc(<kind>) == <name>) {
      Var names = captures.car().list().assoc(<value>);
      List values = parameter.assoc(<sequence>).int()
                  ? names : %($names);
      foreach (Var value, values) {
        String name = value is <list>
          ? Ast.binding_spelling(value) : value;
        c.sym.reference(%($name), NULL);
      }
    }
    parameters = parameters.cdr();
    captures = captures.cdr();
  }
}

/* capture rows

   A capture row keeps an argument's exact source apart from its syntax
   projections. Forwarding a template's own projection rebuilds the row it
   came from, with its Unit construction requirements, and assigns no
   source text to generated syntax. */

/* `retain` keeps each source as the syntax it is and forwards nothing. */
module List _capture_row_project(
  Compiler c, List hole, List sources, int retain) =>
  hole.assoc(<sequence>).int()
    ? _sequence_row(c, sources, retain)
    : _scalar_row(c, sources, retain);

/* A forwarded projection contributes its own sources, values, and
   construction requirements. */
static List _sequence_row(Compiler c, List sources, int retain) {
  Array captured_sources = [], values = [], construction = [];
  foreach (Var captured, sources) {
    List forwarded = retain ? NULL : _forwarded_capture(c, captured);
    match (forwarded)
      case %(capture (source *forwarded_sources)
                     (value *forwarded_values) ? ? *required): {
        foreach (Var item, forwarded_sources) captured_sources.push(item);
        foreach (Var item, forwarded_values) values.push(item);
        foreach (Var item, required) construction.push(item);
        continue;
      }
    captured_sources.push(captured);
    values.push(retain ? captured : _source_unwrap(captured));
  }
  return _capture_layout(
    1, %(source @{captured_sources.list_free()}),
    %(value @{values.list_free()}), NULL, NULL, construction.list_free());
}

/* One source may be a forwarded projection. Any other number of sources
   keeps the sequence layout. */
static List _scalar_row(Compiler c, List sources, int retain) {
  int singular = sources && !sources.cdr();
  Var source = singular ? sources.car() : sources;
  if (singular && !retain) {
    List forwarded = _forwarded_capture(c, source);
    if (forwarded) return forwarded;
  }
  Var value = retain ? source : _source_unwrap(source);
  List values = value is <list> ? value : NULL;
  if (!singular)
    return _capture_layout(
      1, %(source @sources), %(value @values), NULL, NULL, NULL);
  Var expression = _identifier_expression(value);
  return _capture_layout(
    0, %(source $source), %(value $value), %(expression $expression),
    %(splice @values), NULL);
}

static Var _identifier_expression(Var value) {
  if (value is <string>) return %(expr () (ident $value));
  match (value) case %("x2c.ident" ?): return %(expr () (ident $value));
  if (value is <list> && !value.is_nil() &&
      Ast.try_binding(value, NULL, NULL))
    return %(expr () (ident $value));
  return value;
}

/* The row of a projection a template forwards as an argument. A Unit
   hole's source stands for each of its projections. */
static List _forwarded_capture(Compiler c, Var captured) {
  List hole = _forwarded_hole(c, captured);
  if (!hole) return NULL;
  Var source = _hole_key(hole, "source");
  Symbol kind = hole.assoc(<kind>);
  if (kind == <unit>)
    return _capture_layout(
      0, %(source $source), %(value $source), %(expression $source),
      %(splice), %(${_hole_key(hole, "construction")}));
  if (kind != <expr> && kind != <name>) return NULL;
  return _capture_layout(
    0, %(source $source), %(value ${_hole_key(hole, "value")}),
    %(expression ${_hole_key(hole, "expression")}),
    %(splice ${_hole_key(hole, "splice")}), NULL);
}

/* The hole whose projection binder `captured` is, when a template passes
   one of its own projections as an argument. */
static List _forwarded_hole(Compiler c, Var captured) {
  if (!c.macro_holes || captured is not <list> || captured.is_nil())
    return NULL;
  Var direct = void;
  match (captured) {
    case %(expr (<macro-expr>)
           (macro-bind ?slot)): direct = slot;
    case %(macro-bind ?): direct = captured.list().cadr();
  }
  if (direct is void) return NULL;
  String spelling = direct.str(), prefix = _forwarded_prefix(spelling);
  if (!prefix) return NULL;
  return _hole_record(c, Atom.intern(spelling[prefix.len():]));
}

static String _forwarded_prefix(String spelling) {
  foreach (String prefix, forwarded_prefixes)
    if (spelling.startswith(prefix)) return prefix;
  return NULL;
}

/* Forwarding recognizes the projection binders _capture_pattern creates, so
   the accepted prefixes come from Macro.binder; <?> supplies its
   empty author name. */
static List _forwarded_prefix_list(void) {
  Array prefixes = [];
  Map seen = {};
  foreach (String projection, %("expression" "value" "source" "splice"))
    for (int sequence = 0; sequence <= 1; sequence++) {
      String prefix = Macro.binder(<?>, projection, sequence).str();
      if (prefix in seen) continue;
      seen[prefix] = 1;
      prefixes.push(prefix);
    }
  return prefixes.list_free();
}

static List forwarded_prefixes = _forwarded_prefix_list();

/* `(src (source FILE BEGIN END) SYNTAX)` records one complete caller argument
   or decorator target. Constructed syntax can reproduce that List shape, so
   source access trusts only captured syntax identities registered for the
   active expansion. Forwarding preserves the registered capture. */
module int _source_capture_parts(Var value, List &?source, Var &?syntax) {
  match (value)
    case %(src ?record ?captured): {
      if (source) source = record;
      if (syntax) syntax = captured;
      return 1;
    }
  return 0;
}

/* `value` without its source wrappers. A pending invocation or quotation
   inside it keeps its own capture rows or holes, so nested applications
   unwrap each argument once. */
module Var _source_unwrap(Var value) {
  if (value is not <list> || value.is_nil()) return value;
  match (value) {
    case %(src ? ?syntax): return _source_unwrap(syntax);
    case %((!or macro-invoke "x2c.quoted") *): return value;
  }
  List child;
  $ast.rewrite_children(value.list(), child, _source_unwrap(child));
}

/* invocations at syntax positions

   A claimed invocation at file, block, statement, field, enumerator, or
   map-entry position parses its arguments; a decorator also parses the
   target that follows it. */

/** Parses a direct or keyword-alias macro at the requested syntax position.
    Returns NULL without consuming a macro hole or an invocation that
    `macro_starts_target_at` does not claim; template parsing returns a
    deferred `(seq (macro-invoke ...))`, and ordinary parsing returns the bound
    expansion.
*/
List Compiler.try_parse_macro_target_at(Compiler c, Symbol position) =>
  _target_at(c, position, 0);

/* An `open` statement omits its final `;`, as an anonymous Stmt arrow's
   statement does. */
module List _target_at(Compiler c, Symbol position, int open) {
  if (c.macro_holes && c.peek_macro_hole()) return NULL;
  Token invocation = c.token;
  List definition = _take_invocation(c, position);
  if (!definition) return NULL;
  if (definition.assoc(<kind>) == <decorator>)
    return _decorate(c, definition, invocation, position, open);
  _check_position(c, definition, invocation, position);
  return _invoke_definition(c, definition, invocation, position, open);
}

/* A macro's result must fit where it is invoked; a Declaration result also
   fits at file scope. */
static void _check_position(
  Compiler c, List definition, Token invocation, Symbol position) {
  Symbol kind = definition.assoc(<kind>);
  const MacroPos *place = _position(position);
  if (kind == place.kind || (kind == <decl-unit> && position == <unit>))
    return;
  Atom name = definition.assoc(<name>);
  String spelling = name.str(), result_kind = _kind_spelling(kind);
  $fail.macros_result_position(
    c, invocation, spelling, result_kind, place.description);
}

/* Invocation parsing and expansion share one semantic transaction. Empty
   generated syntax and raised diagnostics therefore cannot leave provisional
   bindings, enumerators, statics, or generated-name state behind. */
static List _invoke_definition(
  Compiler c, List definition, Token invocation, Symbol position, int open) {
  int deferred = !!c.macro_holes;
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  List input = _invocation_arguments(c, definition, invocation);
  if (_position(position).semicolon && !open) c.expect(<;>);
  List node = _invocation_node(c, definition, input, invocation);
  List result = deferred ? %(seq $node) :
    c.bind_syntax(node, position, c.return_type);
  if (result.car() != <seq> || result.len() != 1 ||
      transaction.local_macros_changed()) transaction.commit();
  return result;
}

/* Inside a template the node names its definition as the expansion will
   find it: a definition that is itself template syntax by value, a local
   macro by its local name, and any other macro by name. */
static List _invocation_node(
  Compiler c, List definition, List input, Token invocation) {
  Var stored = definition;
  Var site = invocation;
  if (c.macro_holes) {
    stored = _stored_reference(c, definition);
    site = <m-invoke>;
  }
  return %(macro-invoke $stored $input $site);
}

/* A template names a visible local macro, so its expansion applies the
   definition published where it lands, with that expansion's names. */
static Var _stored_reference(Compiler c, List definition) {
  Atom name = definition.assoc(<name>);
  if (definition.assoc(<local>).int() &&
      c.sym.lookup_macro(name) == definition)
    return %(local-macro $name);
  if (definition.assoc(<template>)) return %(!quote $definition);
  return name;
}

static List _decorate(
  Compiler c, List definition, Token invocation, Symbol position, int open) {
  Decoration d = {
    .c = c, .definition = definition, .invocation = invocation,
    .position = position, .kind = definition.assoc(<target>), .open = open};
  int deferred = !!c.macro_holes;
  if (!_on_body(d) && _result_kind(definition) != _position(position).kind)
    _misplaced(d);
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  int block_scope = !c.macro_holes && d.kind == <block>;
  if (block_scope) c.sym.push_new_scope();
  defer if (block_scope) c.sym.pop_scope();
  List node = _decoration_node(d, _arguments(d, block_scope));
  if (deferred) {
    transaction.commit();
    return %(seq $node);
  }
  List result = _bind_decoration(d, node);
  $let(c.token, invocation) {
    transaction.commit();
  }
  return result;
}

static int _on_body(Decoration &d) =>
  d.kind == <block> && d.position == <unit>;

static void _misplaced(Decoration &d) {
  Atom name = d.definition.assoc(<name>);
  String spelling = name.str(), target = _kind_spelling(d.kind);
  $fail.macros_decorator_position(d.c, d.invocation, spelling, target);
}

static List _arguments(Decoration &d, int block_scope) {
  Compiler c = d.c;
  List definition = d.definition;
  List arguments = _invocation_arguments(c, definition, d.invocation);
  if (block_scope) _bind_name_arguments(c, definition, arguments);
  if (c.peek(0) == <;>)
    $fail.macros_decorator_semicolon(
      c, d.invocation, _definition_note(definition));
  if (c.peek(0) == <eof>) {
    Atom name = definition.assoc(<name>);
    String spelling = name.str();
    $fail.macros_decorator_target(
      c, d.invocation, spelling, _definition_note(definition));
  }
  return arguments;
}

static List _decoration_node(Decoration &d, List arguments) {
  Compiler c = d.c;
  d.start = c.token;
  List target = _target(d);
  if (d.position == <statement>) target = c.anchor_origin(target, d.start);
  List target_capture = _capture(d, target);
  List input = %(
    target $arguments
    $target_capture
  );
  return _invocation_node(c, d.definition, input, d.invocation);
}

static List _target(Decoration &d) {
  Compiler c = d.c;
  if (_on_body(d)) {
    d.function = c.parse_function_definition();
    match (d.function) case %(function ? ? ?body): return body;
    return NULL;
  }
  if (d.kind == <function>) return c.parse_function_target();
  if (d.kind == <named-type>) return c.parse_named_type();
  if (d.open) return _arrow_statement(c, 1);
  return _positional_target(c, d.position);
}

static List _positional_target(Compiler c, Symbol position) {
  switch (position) {
    case <unit>:
      $let(c.capture_unit, 1) return c.parse_top_level();
    case <block>: case <statement>:
      return c.parse_governed(position);
    case <field>:      return c.parse_field(c.aggregate_type);
    case <enumerator>: return c.parse_enumerator(c.aggregate_type);
    case <map-entry>:  return c.parse_map_entry();
    default: __builtin_unreachable();
  }
}

/* The target's capture row. A public Unit target of one item also carries
   that item as the construction the template requires. */
static List _capture(Decoration &d, List target) {
  Compiler c = d.c;
  List targets = target.car() == <seq> ? target.cdr() : %($target);
  Array captured_targets = [];
  foreach (Var item, targets)
    captured_targets.push(_capture_source(c, item, d.start, c.token));
  List captured = captured_targets.list_free();
  List target_capture =
    _capture_row_project(c, d.definition.assoc(<targetp>), captured, 0);
  if (d.kind == <unit> && !_private_target(c, target) &&
      captured && !captured.cdr())
    target_capture = target_capture.append(%((construct ${captured.car()})));
  return target_capture;
}

/* Visibility comes from a static declaration,
   seen through a lone `seq` and a foreign alias. */
static int _private_target(Compiler c, List target) {
  int private_target = c.source_private > 0;
  List visibility_target = target;
  match (visibility_target)
    case %(seq ?only): visibility_target = only;
  match (visibility_target)
    case %(falias ?declaration ?): visibility_target = declaration;
  match (visibility_target)
    case %((!or function declare typedef) ?type *):
      private_target |= type.type().is_static();
  return private_target;
}

static List _bind_decoration(Decoration &d, List node) {
  Compiler c = d.c;
  if (!_on_body(d)) return c.bind_syntax(node, d.position, c.return_type);
  return _bind_body(c, node, d.function);
}

/* The body was bound with the function's own result type; bind the
   produced items with it too, so a `return` that needs a conversion still
   gets one. */
static List _bind_body(Compiler c, List node, List decorated) {
  Type declared = _declared_result(decorated);
  List result = NULL;
  $let(c.return_type, declared) {
    result = c.bind_syntax(node, <block>, c.return_type);
  }
  List items = result.car() == <seq> ? result.cdr() : %($result);
  match (decorated) case %(function ?rtype ?declarator ?):
    result = %(seq (function $rtype $declarator (block @items)));
  return result;
}

static Type _declared_result(List decorated) {
  Type declared = NULL;
  match (decorated) case %(function ?rtype ?declarator ?): {
    List declaration = %(declare $rtype (bindings $declarator));
    match (declaration.type_from_ast())
      case %((func *) *result_type):
        declared = result_type.type().declared();
  }
  return declared;
}

/* expression invocations

   In an expression, a `$` name without arguments is a Macro value, and a
   `$` call of a function is an explicit meta call. An Expression macro or
   decorator becomes a `macro-invoke` node that binding expands. */

/** Parses and resolves a direct or keyword-alias expression macro.
    Returns NULL without consuming an identifier that is not an applicable
    alias; a direct `$` invocation must resolve to a visible expression form.
*/
List Compiler.try_parse_macro_expression(Compiler c) {
  Token invocation = c.token;
  if (c.peek(0) == <$>) {
    List value = _named_macro_value(c, invocation);
    if (value) return value;
  }
  if ((c.peek(0) == <$> || c.peek(0) == <@>) && !_peek_invocation(c))
    return _parse_meta_call(c, invocation);
  List definition = _take_invocation(c, <expression>);
  if (!definition) return NULL;
  return c.resolve_expression(
    _expression_invocation(c, definition, invocation), invocation);
}

/* Returns the Macro value a `$` name without arguments names. Otherwise the
   cursor returns to the `$`. */
static List _named_macro_value(Compiler c, Token invocation) {
  Atom name = _name(c);
  if (c.peek(0) != <(>) {
    List value = _macro_value(c, name);
    if (value) return value;
  }
  c.token = invocation;
  return NULL;
}

static List _parse_meta_call(Compiler c, Token invocation) {
  c.next();
  /* A meta function is called by its compile-time binding, even from a
     template, whose other free names bind where the expansion lands. */
  List callee = NULL;
  $let(c.macro_holes, NULL) callee = c.parse_variable();
  Type signature = callee.cadr();
  if (!signature.is_function()) {
    c.token = invocation;
    Atom name = _name(c);
    (void) _lookup(c, name, invocation);
  }
  Array arguments = _meta_arguments(c, signature.car().list().cadr());
  Type result = c.macro_holes ? %(<macro-expr>) : signature.cdr();
  /* Inside a `meta` body the whole body runs at compile time, so a `$`
     call there is an ordinary call, except in a pattern, whose binders
     come from its value. */
  Symbol head = c.meta_body && !c.macro_holes && !c.in_pattern
    ? <call> : <meta-call>;
  List call = %(expr $result ($head $callee
    (args @{arguments.list_free()})));
  return c.resolve_expression(call, invocation);
}

/* Each argument converts to its parameter's type, except in a template. */
static Array _meta_arguments(Compiler c, List parameters) {
  Array arguments = [];
  c.expect(<(>);
  if (c.peek(0) != <)>) loop {
    List argument = _meta_argument(c);
    if (parameters && !c.macro_holes)
      argument = c.convert_expression(argument, parameters.car());
    parameters = parameters.cdr();
    arguments.push(argument);
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  return arguments;
}

/* A hole passed alone passes the value it captures, and a sequence hole
   passes its captured items as one List. */
static List _meta_argument(Compiler c) {
  List hole = c.peek_macro_hole();
  Symbol next = hole ? c.after_hole().type : 0;
  int direct = next == <,> || next == <)>;
  if (direct && hole.assoc(<sequence>).int()) {
    c.expect(<$>);
    c.next();
    return %(expr ("List") (meta-cap (${_hole_key(hole, "value")})));
  }
  Symbol kind = hole ? hole.assoc(<kind>) : 0;
  List argument = direct
    ? %(expr (<macro-expr>) ${_parse_hole(c, kind ? kind : <argument>)})
    : c.parse_assignment();
  if (hole && argument.match(%(expr ? (macro-bind ?)))) {
    Atom projection = Macro.binder(hole.assoc(<binder>), "value", 0);
    argument = %(expr ("List") (meta-cap $projection));
  }
  return argument;
}

static List _expression_invocation(
  Compiler c, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  if (kind == <decorator> && definition.assoc(<target>) == <expr>)
    return _expression_decorator(c, definition, invocation);
  if (c.meta_body && (kind == <unit> || kind == <block-item>))
    return _template_call(c, definition);
  List arguments = _invocation_arguments(c, definition, invocation);
  if (kind != <expression>) _not_expression(c, definition, invocation);
  List node = _invocation_node(c, definition, arguments, invocation);
  return %(expr (<macro-expr>) $node);
}

/* In a `meta` body, invoking a Unit or Stmt macro is a template call,
   whose syntax the meta function builds when it runs. */
static List _template_call(Compiler c, List definition) {
  Array arguments = [];
  c.expect(<(>);
  foreach (List hole, definition.assoc(<parameters>).list()) {
    if (arguments.len()) c.expect(<,>);
    arguments.push(c.parse_assignment());
  }
  c.expect(<)>);
  Var stored = definition.assoc(<local>).int()
    ? definition : definition.assoc(<name>);
  return %(expr ("List") (tpl-call $stored
    (args @{arguments.list_free()})));
}

static void _not_expression(
  Compiler c, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  String spelling = definition.assoc(<name>).str();
  $fail.macros_result_expr(
    c, invocation, kind, spelling, _definition_note(definition));
}

static List _expression_decorator(
  Compiler c, List definition, Token invocation) {
  List arguments = _invocation_arguments(c, definition, invocation);
  if (c.peek(0) == <;> || c.peek(0) == <eof>) {
    String spelling = definition.assoc(<name>).str();
    $fail.macros_decorator_expr(
      c, invocation, spelling, _definition_note(definition));
  }
  List target = c.parse_macro_expression_target();
  List input = %(
    target $arguments
    ${_capture_row_project(c, definition.assoc(<targetp>), %($target), 0)}
  );
  List node = _invocation_node(c, definition, input, invocation);
  return %(expr (<macro-expr>) $node);
}
