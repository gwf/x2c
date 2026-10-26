/*  captures.x -- macro invocation captures */

static keyword loop $private.loop;

/* invocation arguments

   Each parameter hole captures its arguments into one capture row, and a
   captured argument records the source span it was parsed from. */

module List _invocation_arguments(
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
  return %(args @(arguments.list_free()));
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
    foreach (List directive in c.leading_preproc()) captured.push(directive);
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
  with (c.shallow = 0) {
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
  List visible = c.sym.lookup($(spelling), NULL);
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

module Var _capture_source(
  Compiler c, Var syntax, Token first, Token after) {
  if (c.macro_holes || syntax is not <list> ||
      syntax.is_nil() || !first) return syntax;
  Token last = _previous_source_token(c, after);
  if (!last || last < first) return syntax;
  int end = last.pos + last.len;
  String file = c.source_path(c.filename ? c.filename : "<stdin>");
  List source = %(source $file $(first.pos) $end);
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
  foreach (Var captured in sources) {
    List forwarded = retain ? NULL : _forwarded_capture(c, captured);
    match (forwarded)
      case %(capture (source *forwarded_sources)
                     (value *forwarded_values) ? ? *required): {
        foreach (Var item in forwarded_sources) captured_sources.push(item);
        foreach (Var item in forwarded_values) values.push(item);
        foreach (Var item in required) construction.push(item);
        continue;
      }
    captured_sources.push(captured);
    values.push(retain ? captured : _source_unwrap(captured));
  }
  return _capture_layout(
    1, %(source @(captured_sources.list_free())),
    %(value @(values.list_free())), NULL, NULL, construction.list_free());
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
  if (value ~= %("x2c.ident" ?)) return %(expr () (ident $value));
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
      %(splice), $(_hole_key(hole, "construction")));
  if (kind != <expr> && kind != <name>) return NULL;
  return _capture_layout(
    0, %(source $source), %(value $(_hole_key(hole, "value"))),
    %(expression $(_hole_key(hole, "expression"))),
    %(splice $(_hole_key(hole, "splice"))), NULL);
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
  foreach (String prefix in forwarded_prefixes)
    if (spelling.startswith(prefix)) return prefix;
  return NULL;
}

/* Forwarding recognizes the projection binders _capture_pattern creates, so
   the accepted prefixes come from Macro.binder; <?> supplies its
   empty author name. */
static List _forwarded_prefix_list(void) {
  Array prefixes = [];
  Map seen = {};
  foreach (String projection in %("expression" "value" "source" "splice"))
    for (int sequence = 0; sequence <= 1; sequence++) {
      String prefix = Macro.binder(<?>, projection, sequence).str();
      if (prefix in seen) continue;
      seen[prefix] = 1;
      prefixes.push(prefix);
    }
  return prefixes.list_free();
}

static List forwarded_prefixes = _forwarded_prefix_list();

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
