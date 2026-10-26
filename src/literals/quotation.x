/*  quotation.x -- quoted Lists and typed patterns */

static keyword loop $private.loop;

// diagnostics

static macro Stmt $fail.literals_macro_pattern_static(
  Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>,
    "a macro pattern's arguments are binders, macro patterns, or %(...)",
    $origin, NULL);

static macro Stmt $fail.literals_insert_name(
  Expr $c, Expr $site, Expr $sigil) {
  {
    String message = %"expected identifier after '$($sigil)'";
    String hint = $sigil == <@>
      ? "use '@(...)' to splice an expression"
      : "use '$(...)' to insert an expression";
    $c.report_error(<parse>, message, $site, $(hint));
  }
}

/* list literals

   `%(...)` and a nested `(...)` read quoted data into typed cons cells. In
   a pattern, a List headed by `!is` accepts the reserved binder spellings,
   and one headed by `!quote` records no typed captures. */

/** Parses a `List` literal beginning at `(` or `%(` and returns its typed
    expression after consuming `)`. Pattern parsing sets and restores
    `match_is`; `runtime_literals` disables stable-cell caching.
*/
List Compiler.parse_list_literal(Compiler c) {
  int percent = c.peek(0) == <"%(">;
  c.next();
  if (c.test(<)>)) return %(expr ("List") (nil));
  Symbol operator = _match_operator_head(c);
  with (c.match_is = operator == <!is>,
        c.match_types = operator == <!quote> ? NULL : c.match_types) {
    // A `%(` literal that holds only a reader form is that form.
    List reader_form = percent ? _parse_reader_prefix(c) : NULL;
    if (reader_form && c.test(<)>)) return reader_form;
    int shell = c.in_pattern && !reader_form && c.peek(0) == <ident> &&
                c.token.text == "expr";
    List head = reader_form ? reader_form : _parse_list_head(c);
    List tail = shell ? _parse_shell_tail(c) : _parse_list_tail(c);
    c.expect(<)>);
    return %(expr ("List") $(c.literal_cell(head, tail)));
  }
}

/* A pattern List may open with a match operator, spelled as an Atom or as
   a `<...>` Symbol. */
static Symbol _match_operator_head(Compiler c) {
  if (!c.in_pattern) return 0;
  if (c.peek(0) == <lit-atom>) {
    Atom atom = Atom.intern(c.token.text.unescape());
    return atom is <symbol> ? atom.symbol() : 0;
  }
  if (c.peek(0) != <lit-symbol>) return 0;
  Token token = c.token;
  return _exact_symbol(c, token, _angle_spelling(token.text));
}

/* A Lisp reader prefix reads as the List it abbreviates: `'x` is
   `(quote x)`. */
static List _parse_reader_prefix(Compiler c) {
  String spelling = NULL;
  switch (c.peek(0)) {
    case <"'">:  spelling = "quote";            break;
    case <"`">:  spelling = "quasiquote";       break;
    case <",">:  spelling = "unquote";          break;
    case <",@">: spelling = "unquote-splicing"; break;
    default: return NULL;
  }
  c.next();
  List value = _parse_list_head(c);
  List tail = c.literal_cell(value, %(nil));
  return c.literal_cell(_atom_element(c, spelling), tail);
}

/* An Atom element that the parser adds, such as a reader form's name or a
   typed capture's `!is`, cached unless literals are built at runtime. */
static List _atom_element(Compiler c, String spelling) {
  Atom atom = Atom.intern(spelling);
  List literal = atom is <symbol>
    ? %(literal ("Symbol") $spelling $(atom.symbol()))
    : %(literal ("Atom") $spelling $atom);
  List expression = %(expr $(literal.cadr()) $literal);
  if (c.runtime_literals) return expression;
  return c.cache(%(var $expression));
}

module List _parse_list_head(Compiler c) {
  c.require_input();
  List reader_form = _parse_reader_prefix(c);
  if (reader_form) return reader_form;
  List splice = _parse_splice(c);
  if (splice) return %(expr ("List") $splice);
  List inserted = _parse_insertion(c);
  if (inserted) return inserted;
  return _cache_if_stable(c, _parse_literal_element(c));
}

static List _cache_if_stable(Compiler c, List elem) {
  Var matched;
  List bindings;
  /* A reference is `(ident <binding-list>)`. The binding sublist has to be
     part of the search: `%(ident *)` also matches the final cell of a
     literal node ending in the Symbol <ident>. */
  if (elem.try_search(
    $source_identifier_content(%((*))), matched, bindings)) return elem;
  if (c.runtime_literals || c.needs_resolution(elem)) return elem;
  /* Each evaluation builds a fresh Array or Map, so a List that holds one,
     at any depth, is built at runtime too. */
  if (elem ~= %(expr (!or ("Array") ("Map")) *) ||
      elem ~= %(expr ("List") (expr ("List") (cons *))))
    return elem;
  return c.cache(%(var $elem));
}

static List _parse_list_tail(Compiler c) {
  if (c.peek(0) == <)>) return %(nil);
  List head = _parse_list_head(c), tail = _parse_list_tail(c);
  return c.literal_cell(head, tail);
}

/* The elements after a pattern's `expr` head. A macro pattern in the
   content position stands for the content, since the pattern writes the
   shell itself. */
static List _parse_shell_tail(Compiler c) {
  if (c.peek(0) == <)>) return %(nil);
  List type = _parse_list_head(c);
  if (c.peek(0) == <)>) return c.literal_cell(type, %(nil));
  List content = c.try_parse_macro_pattern_insertion(1);
  if (!content) content = _parse_list_head(c);
  return c.literal_cell(type, c.literal_cell(content, _parse_list_tail(c)));
}

/** Parses a macro pattern's parenthesized arguments and returns the static
    pattern of each: a binder or wildcard, a nested macro pattern, or a
    `%(...)` List pattern.
*/
List Compiler.parse_macro_pattern_arguments(Compiler c) {
  c.expect(<(>);
  Array patterns = [];
  if (c.peek(0) != <)>) loop {
    patterns.push(_macro_pattern_argument(c));
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  return patterns.list_free();
}

static Var _macro_pattern_argument(Compiler c) {
  Token origin = c.token;
  if (c.peek(0) == <?> || c.peek(0) == <*>) {
    String binder = origin.text;
    c.next();
    if (c.peek(0) == <ident>) {
      binder = binder + c.token.text;
      c.next();
    }
    return Atom.intern(binder);
  }
  List element = c.try_parse_macro_subpattern(0);
  if (!element) {
    if (c.peek(0) != <"%(">) $fail.literals_macro_pattern_static(c, origin);
    element = c.parse_list_literal();
  }
  Var value = c.match_pattern_value(element);
  if (!Compiler.match_value_is_static(value))
    $fail.literals_macro_pattern_static(c, origin);
  return value;
}

/** Parses a pattern's `$($NAME(...))`, where NAME is a macro, into its
    derived pattern, or returns NULL without consuming tokens. `content`
    selects the bare content, for the content position of an
    `(expr TYPE ...)` shell.
*/
List Compiler.try_parse_macro_pattern_insertion(Compiler c, int content) {
  /* `%(...)` scans `$(` as one token; a whole `case` pattern has two. */
  int joined = c.peek(0) == <"$(">;
  if (!c.in_pattern || (!joined && (c.peek(0) != <$> || c.peek(1) != <(>)))
    return NULL;
  Token name = Token.skip_trivia(c.token + 1);
  if (!joined) name = Token.skip_trivia(name + 1);
  String spelling = NULL;
  Var stored;
  if (!c.macro_pattern_at(name, spelling, stored)) return NULL;
  c.next();
  if (!joined) c.next();
  List derived = c.try_parse_macro_subpattern(content);
  c.expect(<)>);
  return derived;
}

/* list elements

   `$` inserts one value and `@` splices a List, each followed by a name or
   a parenthesized expression. `${` opens an evaluated Map, and any other
   element is a nested literal. */

static List _parse_splice(Compiler c) {
  if (c.peek(0) == <@>) {
    List expr = _parse_named_reference(c, <@>);
    return %(splice $expr);
  }
  if (!c.test(<"@(">)) return NULL;
  List expr = c.parse_expression();
  c.expect(<)>);
  return %(splice $expr);
}

module List _parse_insertion(Compiler c) {
  if (c.peek(0) == <$>)
    return _parse_named_reference(c, <$>);
  List derived = c.try_parse_macro_pattern_insertion(0);
  if (derived) return derived;
  if (!c.test(<"$(">)) return NULL;
  List expr = c.parse_expression();
  c.check_explicit_converter(expr, %("Var"), 0);
  c.expect(<)>);
  return expr;
}

/** Parses an evaluated List `$(a, b, ...)`: each assignment expression is
    one element, converted to Var, and `@name` or `@(expression)` splices a
    List's elements, as in a quoted List. A trailing comma is allowed, and
    `$()` is the empty List.
*/
List Compiler.parse_evaluated_list(Compiler c) {
  c.expect(<$>);
  c.expect(<(>);
  Array elements = auto [];
  while (c.peek(0) != <)>) {
    elements.push(_evaluated_element(c));
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  return c.list_expression(elements, %(nil));
}

/* In code `@(` is two tokens. */
static List _evaluated_element(Compiler c) {
  if (c.peek(0) == <@> && (c.token + 1).type == <(>) {
    c.next();
    c.next();
    List expr = c.parse_expression();
    c.expect(<)>);
    return %(splice $expr);
  }
  if (c.peek(0) == <@>) return %(splice $(_parse_named_reference(c, <@>)));
  List element = c.parse_assignment();
  c.check_explicit_converter(element, %("Var"), 0);
  return element;
}

module List _parse_named_reference(Compiler c, Symbol sigil) {
  c.expect(sigil);
  if (c.peek(0) != <ident>)
    $fail.literals_insert_name(c, c.token, sigil);
  return c.parse_variable();
}

module List _parse_literal_element(Compiler c) {
  switch (c.peek(0)) {
    case <"?(">:  return _parse_typed_capture(c);
    case <"(">:   return c.parse_list_literal();
    case <"%\"">: return c.parse_string_literal();
    case <"%[">:  return c.parse_array_literal();
    case <"%{">:  return c.parse_map_literal();
    case <"${">:  return c.parse_evaluated_map();
    default:      return c.parse_atomic_literal();
  }
}

/* list cells

   A cell conses one element onto the cells after it. When the element and
   the tail both have cache forms, the cell folds into the cache too. */

/** Conses the element expression `head` onto the cells `tail`, or appends
    the List a `(splice EXPR)` head holds, and folds the cell into the
    literal cache when both parts are constant.
*/
List Compiler.literal_cell(Compiler c, List head, List tail) {
  if (head ~= %(!or (splice ?sexpr) (expr ("List") (splice ?sexpr))))
    return _append_splice(c, sexpr, tail);
  if (head ~= %(expr (<macro-expr>) ?))
    return %(expr ("List") (cons $head $tail));
  /* A nested `List` that already folded enters the cache as its own key, the
     way a parsed element does, so the enclosing cell folds too. Converting it
     to `Var` first would leave a `List_var` call the cache cannot represent,
     and a typed-capture pattern that _typed_list rebuilds would not fold. */
  if (head ~= %(expr ("List") (expr ("List") (cache *))))
    head = c.cache(%(var $head));
  head = c.convert_expression(head, %("Var"));
  List cached = c.cache_cons_cell(head, tail);
  if (cached) return cached;
  return %(expr ("List") (cons $head $tail));
}

static List _append_splice(Compiler c, List head, List tail) {
  if (c.sym.is_var_type(head.cadr()))
    head = %(expr ("List") (call "Var_list_payload" (args $head)));
  else head = c.convert_expression(head, %("List"));
  return %(expr ("List") (append $head $tail));
}

/** Builds the typed List expression that conses the element expressions
    `elements`, in order, onto the cells `tail`. A `(splice EXPR)` element
    appends the List that EXPR holds, as `literal_cell` does.
*/
List Compiler.list_expression(Compiler c, Array elements, List tail) {
  for (int i = (int) elements.len() - 1; i >= 0; i--)
    tail = c.literal_cell(elements[i], tail);
  return %(expr ("List") $tail);
}

/* typed captures

   `?(Type name)` binds `?name` only to a value with that type's Var tag.
   In a source `match` arm, the arm records `(name Type)` and
   `typed_match_pattern` adds the test to every occurrence; elsewhere the
   capture becomes the pattern `(!is ?name type TAG)`. */

static List _parse_typed_capture(Compiler c) {
  Token origin = c.token;
  c.expect(<"?(">);
  Type type = c.parse_type_name();
  String name = c.token.text;
  c.expect(<ident>);
  c.expect(<")">);
  Atom binder = Atom.intern(%"?$name");
  List tag = c.var_tag_expression(type, origin);
  if ((void *) c.match_types) {
    List row = $(name, type);
    if (!_recorded(c, name, type, tag, origin)) c.match_types.push(row);
    return _atom_element(c, binder.str());
  }
  return _tag_test(c, binder, tag);
}

/* An arm records a binder once for each Var tag and declared type. */
static int _recorded(
  Compiler c, String name, Type type, List tag, Token origin) {
  foreach (List previous in c.match_types)
    if (previous ~= %(?previous_name ?previous_type))
    if (previous_name == name &&
        c.var_tag_expression(previous_type, origin) == tag &&
        c.sym.normalize_declared_type(previous_type) ==
        c.sym.normalize_declared_type(type)) return 1;
  return 0;
}

/* `(!is ?binder type TAG)`, or `(!is type TAG)` without a binder. */
static List _tag_test(Compiler c, Atom binder, List tag) {
  List elements = binder.is_atom_binder() ? %(!is $binder type) : %(!is type);
  if (tag ~= %(expr ("Symbol") ?)) tag = c.cache(%(var $tag));
  List tail = c.literal_cell(tag, %(nil));
  foreach (Var element in elements.reverse())
    tail = c.literal_cell(_atom_element(c, element.str()), tail);
  return %(expr ("List") $tail);
}

/** Applies each typed capture's predicate to every unquoted occurrence. */
List Compiler.typed_match_pattern(Compiler c, List pattern, List types) {
  Map tags = {};
  foreach (List row in types)
    if (row ~= %(?name ?type))
    tags[Atom.intern(%"?$(name)")] = c.var_tag_expression(type, c.token);
  return _typed_pattern(c, pattern, tags);
}

static List _typed_pattern(Compiler c, List node, Map tags) {
  Var value = c.match_pattern_value(node), tag;
  if (value.is_atom_binder() && tags.try_get(value, tag))
    return _tag_test(c, value, tag);
  List content = _pattern_content(c, node);
  if (content ~= %(cons ? ?)) return _typed_list(c, node, content, tags);
  return node;
}

/* A pattern hides under typed, cached, and boxed wrappers. */
static List _pattern_content(Compiler c, List node) {
  match (node) {
    case %(expr ("Var") (call ? (args ?value))):
      return c.is_builtin_converter_call(node)
        ? _pattern_content(c, value) : node;
    case %(expr ? ?value): return _pattern_content(c, value);
    case %(cache ?id): return _pattern_content(c, c.id_keys[id]);
    case %(var ?value): return _pattern_content(c, value);
  }
  return node;
}

/* An operator's operands follow it and its binder, which `!set` has only
   before a single pattern. `!quote` and `!is` operands stay as written,
   and a typed binder's test joins the whole pattern. */
static List _typed_list(
  Compiler c, List node, List content, Map tags) {
  Array elements = auto [];
  List tail = _pattern_elements(c, content, elements);
  Var operator = c.match_pattern_value(elements[0]), tag;
  if (operator == <!quote>) return node;
  int first = operator.is_match_op() ? 1 : 0;
  List capture_tag = NULL;
  if (first && elements.len() > 1) {
    Var binder = c.match_pattern_value(elements[1]);
    if (binder.is_atom_binder() &&
        (operator != <!set> || elements.len() == 3)) {
      if (tags.try_get(binder, tag)) capture_tag = tag;
      first++;
    }
  }
  if (operator != <!is>)
    for (int i = first; i < elements.len(); i++)
      elements[i] = _typed_pattern(c, elements[i], tags);
  List pattern = c.list_expression(elements, tail);
  return capture_tag ? _and_tag_test(c, pattern, capture_tag) : pattern;
}

/* Pushes the heads of a cons chain and returns what ends it. */
static List _pattern_elements(Compiler c, List tail, Array elements) {
  loop {
    if (tail ~= %(cons ?head ?rest)) {
      elements.push(head);
      tail = _pattern_content(c, rest);
      continue;
    }
    return tail;
  }
}

/* `(!and (!is type TAG) PATTERN)` */
static List _and_tag_test(Compiler c, List pattern, List tag) {
  List tail = c.literal_cell(pattern, %(nil));
  tail = c.literal_cell(_tag_test(c, void, tag), tail);
  tail = c.literal_cell(_atom_element(c, "!and"), tail);
  return %(expr ("List") $tail);
}
