/*  literals.x -- x2c literal parsing

    Each literal parses to a typed expression. A `List` cell or `String`
    segment with no dynamic reference enters the compiler cache and is built
    once; `runtime_literals` builds every one at run time instead. Lambda
    literals parse in `lambdas.x`.
*/
#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#pragma private
$(import "../src/grammar.xmacro")
#include "parse.x"
#include "type.x"
#include "expressions.x"
#include "transform.x"
#include "lambdas.x"
#include <stdint.h>
#include <string.h>

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
  $let(c.match_is, operator == <!is>)
  $let(c.match_types, operator == <!quote> ? NULL : c.match_types) {
    // A `%(` literal that holds only a reader form is that form.
    List reader_form = percent ? _parse_reader_prefix(c) : NULL;
    if (reader_form && c.test(<)>)) return reader_form;
    List head = reader_form ? reader_form : _parse_list_head(c);
    List tail = _parse_list_tail(c);
    c.expect(<)>);
    return %(expr ("List") ${_cons_cell(c, head, tail)});
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
  List tail = _cons_cell(c, value, %(nil));
  return _cons_cell(c, _atom_element(c, spelling), tail);
}

/* An Atom element that the parser adds, such as a reader form's name or a
   typed capture's `!is`, cached unless literals are built at runtime. */
static List _atom_element(Compiler c, String spelling) {
  Atom atom = Atom.intern(spelling);
  List literal = atom is <symbol>
    ? %(literal ("Symbol") $spelling ${atom.symbol()})
    : %(literal ("Atom") $spelling $atom);
  List expression = %(expr ${literal.cadr()} $literal);
  if (c.runtime_literals) return expression;
  return c.cache(%(var $expression));
}

static List _parse_list_head(Compiler c) {
  List elem = NULL;
  if ((elem = _parse_reader_prefix(c))) return elem;
  if ((elem = _parse_splice(c))) return %(expr ("List") $elem);
  if ((elem = _parse_insertion(c))) return elem;
  return _cache_if_stable(c, _parse_literal_element(c));
}

static List _cache_if_stable(Compiler c, List elem) {
  Var matched;
  List bindings;
  /* A reference is `(ident <binding-list>)`. The binding sublist has to be
     part of the search: `%(ident *)` also matches the final cell of a
     literal node ending in the Symbol <ident>. */
  if (elem.try_search($source_identifier_content(%((*))),
      matched, bindings)) return elem;
  if (c.runtime_literals) return elem;
  /* Each evaluation builds a fresh Array or Map, so a List that holds one,
     at any depth, is built at runtime too. */
  if (elem.match(%(expr (!or ("Array") ("Map")) *)) ||
      elem.match(%(expr ("List") (expr ("List") (cons *)))))
    return elem;
  return c.cache(%(var $elem));
}

static List _parse_list_tail(Compiler c) {
  if (c.peek(0) == <)>) return %(nil);
  List head = _parse_list_head(c), tail = _parse_list_tail(c);
  return _cons_cell(c, head, tail);
}

/* list elements

   `$` inserts one value and `@` splices a List, each followed by a name or
   a braced expression. Any other element is a nested literal. */

static List _parse_splice(Compiler c) {
  if (c.peek(0) == <@>) {
    List expr = _parse_named_reference(
      c, <@>, "use '@{...}' to splice an expression");
    return %(splice $expr);
  }
  if (!c.test(<"@{">)) return NULL;
  List expr = c.parse_expression();
  c.expect(<"}">);
  return %(splice $expr);
}

static List _parse_insertion(Compiler c) {
  if (c.peek(0) == <$>)
    return _parse_named_reference(
      c, <$>, "use '${...}' to insert an expression");
  if (c.peek(0) != <"${"> || c.token.len != 2) return NULL;
  c.next();
  List expr = c.parse_expression();
  c.check_explicit_converter(expr, %("Var"), 0);
  c.expect(<"}">);
  return expr;
}

static List _parse_named_reference(Compiler c, Symbol sigil, String hint) {
  c.expect(sigil);
  if (c.peek(0) != <ident>) {
    String message = %"expected identifier after '$sigil'";
    c.report_error(<parse>, message, c.token, %( $hint ));
  }
  return c.parse_variable();
}

static List _parse_literal_element(Compiler c) {
  switch (c.peek(0)) {
    case <"?(">:  return _parse_typed_capture(c);
    case <"(">:   return c.parse_list_literal();
    case <"%\"">: return c.parse_string_literal();
    case <"%[">:  return c.parse_array_literal();
    case <"%{">:  return c.parse_map_literal();
    default:      return c.parse_atomic_literal();
  }
}

/* An Array or Map element has no splice form. */
static List _parse_element(Compiler c) {
  List inserted = _parse_insertion(c);
  return inserted ? inserted : _parse_literal_element(c);
}

/* list cells

   A cell conses one element onto the cells after it. When the element and
   the tail both have cache forms, the cell folds into the cache too. */

static List _cons_cell(Compiler c, List head, List tail) {
  match (head)
    case %(!or (splice ?sexpr) (expr ("List") (splice ?sexpr))):
      return _append_splice(c, sexpr, tail);
  if (head.match(%(expr (<macro-expr>) ?)))
    return %(expr ("List") (cons $head $tail));
  /* A nested `List` that already folded enters the cache as its own key, the
     way a parsed element does, so the enclosing cell folds too. Converting it
     to `Var` first would leave a `List_var` call the cache cannot represent,
     and a typed-capture pattern that _typed_list rebuilds would not fold. */
  if (head.match(%(expr ("List") (expr ("List") (cache *)))))
    head = c.cache(%(var $head));
  head = c.convert_expression(head, %("Var"));
  List cached = c.cache_cons_cell(head, tail);
  if (cached) return cached;
  return %(expr ("List") (cons $head $tail));
}

static List _append_splice(Compiler c, List head, List tail) {
  if (c.sym.is_var_type(head.cadr()))
    head = %(expr ("List") (call "Var_list" (args $head)));
  else head = c.convert_expression(head, %("List"));
  return %(expr ("List") (append $head $tail));
}

static List _cons_list(Compiler c, Array elements, List tail) {
  for (int i = (int) elements.len() - 1; i >= 0; i--)
    tail = _cons_cell(c, elements[i], tail);
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
    List row = %($name $type);
    if (!_recorded(c, name, type, tag, origin)) c.match_types.push(row);
    return _atom_element(c, binder.str());
  }
  return _tag_test(c, binder, tag);
}

/* An arm records a binder once for each Var tag and declared type. */
static int _recorded(
  Compiler c, String name, Type type, List tag, Token origin) {
  int repeated = 0;
  foreach (List previous, c.match_types) match (previous)
    case %(?previous_name ?previous_type):
      if (previous_name == name &&
          c.var_tag_expression(previous_type, origin) == tag &&
          c.sym.normalize_declared_type(previous_type) ==
          c.sym.normalize_declared_type(type)) repeated = 1;
  return repeated;
}

/* `(!is ?binder type TAG)`, or `(!is type TAG)` without a binder. */
static List _tag_test(Compiler c, Atom binder, List tag) {
  List elements = binder.is_atom_binder() ? %(!is $binder type) : %(!is type);
  match (tag)
    case %(expr ("Symbol") ?): tag = c.cache(%(var $tag));
  List tail = _cons_cell(c, tag, %(nil));
  foreach (Var element, elements.reverse())
    tail = _cons_cell(c, _atom_element(c, element.str()), tail);
  return %(expr ("List") $tail);
}

/** Applies each typed capture's predicate to every unquoted occurrence. */
List Compiler.typed_match_pattern(Compiler c, List pattern, List types) {
  Map tags = {};
  foreach (List row, types) match (row)
    case %(?name ?type):
      tags[Atom.intern(%"?${name}")] = c.var_tag_expression(type, c.token);
  return _typed_pattern(c, pattern, tags);
}

static List _typed_pattern(Compiler c, List node, Map tags) {
  Var value = c.match_pattern_value(node), tag;
  if (value.is_atom_binder() && tags.try_get(value, tag))
    return _tag_test(c, value, tag);
  List content = _pattern_content(c, node);
  match (content)
    case %(cons ? ?): return _typed_list(c, node, content, tags);
  return node;
}

/* A pattern hides under typed, cached, and boxed wrappers. */
static List _pattern_content(Compiler c, List node) {
  match (node) {
    case %(expr ? ?value): return _pattern_content(c, value);
    case %(cache ?id): return _pattern_content(c, c.id_keys[id]);
    case %(var ?value): return _pattern_content(c, value);
    case %(call (expr ? ${$source_identifier_content(%(?binding))})
        (args ?value)):
      if (binding_identity_spelling(binding) == "List_var")
        return _pattern_content(c, value);
  }
  return node;
}

/* An operator's operands follow it and its binder, which `!set` has only
   before a single pattern. `!quote` and `!is` operands stay as written,
   and a typed binder's test joins the whole pattern. */
static List _typed_list(Compiler c, List node, List content, Map tags) {
  Array elements = $auto([]);
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
  List pattern = _cons_list(c, elements, tail);
  return capture_tag ? _and_tag_test(c, pattern, capture_tag) : pattern;
}

/* Pushes the heads of a cons chain and returns what ends it. */
static List _pattern_elements(Compiler c, List tail, Array elements) {
  loop {
    match (tail) case %(cons ?head ?rest): {
      elements.push(head);
      tail = _pattern_content(c, rest);
      continue;
    }
    return tail;
  }
}

/* `(!and (!is type TAG) PATTERN)` */
static List _and_tag_test(Compiler c, List pattern, List tag) {
  List tail = _cons_cell(c, pattern, %(nil));
  tail = _cons_cell(c, _tag_test(c, void, tag), tail);
  tail = _cons_cell(c, _atom_element(c, "!and"), tail);
  return %(expr ("List") $tail);
}

/* error payloads

   A `raise` payload and a filtered `catch` read a code and then detail
   pairs. A pair's key is a bare Symbol, and its one value or pattern
   cannot splice. Payload literals are built at runtime. */

/** Parses the `%()` payload following `raise` into a `(raise CODE (args ...))`
    node and consumes its closing `)`. The code is a bare `Symbol` or a
    `$name` reference, detail keys are bare `Symbol`s, each keyed detail has
    one value, and payload literals bypass the compiler cache.
*/
List Compiler.parse_raise_literal(Compiler c) {
  c.expect(<"%(">);
  $let(c.runtime_literals, 1) {
    List code = _parse_raise_code(c);
    Array args = [];
    while (c.peek(0) != <)>) {
      List slot = c.try_parse_macro_slot(<argument>);
      if (slot) args.push(slot);
      else _parse_raise_detail(c, args);
    }
    c.expect(<)>);
    List values = args;
    args.free();
    return %(raise $code (args @values));
  }
}

static List _parse_raise_code(Compiler c) {
  List code = c.try_parse_macro_slot(<expression>);
  if (!code) code = _parse_insertion(c);
  if (code) return code;
  return _parse_bare_symbol(
    c, "raise", "code", "use raise %(code (key value)...);");
}

static void _parse_raise_detail(Compiler c, Array args) {
  Token origin = c.token;
  c.expect(<(>);
  List key = c.try_parse_macro_slot(<expression>);
  if (!key)
    key = _parse_bare_symbol(
      c, "raise", "detail key", "use raise %(code (key value)...);");
  List value = _parse_detail_value(
    c, origin, "raise detail requires exactly one value",
    "raise detail value cannot splice", %("pass one value expression"));
  args.push(key);
  args.push(value);
}

static List _parse_bare_symbol(
  Compiler c, String owner, String role, String hint) {
  Token token = c.token;
  if (c.peek(0) != <lit-atom>)
    c.report_error(
      <parse>, %"$owner $role must be a bare Symbol", token, %($hint));
  String text = token.text.unescape();
  Symbol symbol = _exact_symbol(c, token, text);
  c.next();
  return %(expr ("Symbol") (literal ("Symbol") $text $symbol));
}

/* The value or pattern after a detail key, and the pair's `)`. Each report
   locates the pair at its `(`. */
static List _parse_detail_value(
  Compiler c, Token origin, String arity, String spliced, List note) {
  if (c.peek(0) == <)>) c.report_error(<parse>, arity, origin, NULL);
  List value = _parse_list_head(c);
  if (value.match(%(expr ("List") (splice *))) || value.match(%(splice *)))
    c.report_error(<parse>, spliced, origin, note);
  if (c.peek(0) != <)>) c.report_error(<parse>, arity, origin, NULL);
  c.expect(<)>);
  return value;
}

/** Parses a filtered-catch `%()` payload into a typed `List` pattern.
    The call consumes the closing `)`. A code `Symbol`, binder, or pattern
    may be followed by `*` patterns or `(key pattern)` pairs; pattern and
    runtime-literal state is restored on every exit.
*/
List Compiler.parse_catch_pattern_literal(Compiler c) {
  c.expect(<"%(">);
  $let(c.in_pattern, 1)
  $let(c.runtime_literals, 1) {
    List code = _parse_catch_code(c);
    Array elements = [];
    elements.push(code);
    while (c.peek(0) != <)>) _parse_catch_detail(c, elements);
    c.expect(<)>);
    List pattern = _cons_list(c, elements, %(nil));
    elements.free();
    return pattern;
  }
}

static List _parse_catch_code(Compiler c) {
  if (c.peek(0) != <lit-atom>) return _parse_list_head(c);
  return _parse_bare_symbol(
    c, "catch filter", "code", "use catch %(code (key pattern)...):");
}

/* A `*` pattern stands alone, and a `(key pattern)` pair becomes a
   two-element pattern. */
static void _parse_catch_detail(Compiler c, Array elements) {
  Token origin = c.token;
  if (c.peek(0) == <lit-atom> && c.token.text.unescape()[0] == '*') {
    elements.push(_parse_list_head(c));
    return;
  }
  if (!c.test(<(>))
    c.report_error(
      <parse>, "catch filter detail must be '*' or '(key pattern)'",
      origin, %("wrap keyed detail patterns in parentheses"));
  List key = _parse_bare_symbol(
    c, "catch filter", "detail key", "use catch %(code (key pattern)...):");
  List value = _parse_detail_value(
    c, origin, "catch filter detail requires exactly one pattern",
    "catch filter detail pattern cannot splice",
    %("write one match pattern"));
  Array pair = [key, value];
  elements.push(_cons_list(c, pair, %(nil)));
  pair.free();
}

/* Symbol sets

   `%<<...>>` builds an immutable SymbolSet, one C string that holds a
   header, a hash table, and the Symbols in source order. `SymbolSet.encode`
   in `lib/symbolset.x` builds it. */

/** Parses a `%<<...>>` literal into an immutable ordered `SymbolSet`.
    Entries must be literal compact `Symbol`s; source order defines dense
    indexes and an equal encoded `Symbol` reports a duplicate diagnostic.
*/
List Compiler.parse_symbol_set_literal(Compiler c) {
  c.expect(<"%<<">);
  Array symbols = [], tokens = [];
  while (c.peek(0) != <">>">) {
    symbols.push(_member_symbol(c));
    tokens.push(c.token);
    c.next();
  }
  c.expect(<">>">);
  int duplicate = -1;
  List set = c.symbol_set_expression(symbols, duplicate);
  if (duplicate >= 0) {
    Token token = tokens[duplicate];
    Symbol symbol = symbols[duplicate];
    c.report_error(
      <parse>, "duplicate Symbol in symbol set", token,
      %("symbol:" ${symbol.repr()}));
  }
  symbols.free();
  tokens.free();
  return set;
}

static Symbol _member_symbol(Compiler c) {
  Token token = c.token;
  Symbol kind = c.peek(0);
  if (kind != <lit-atom> && kind != <lit-symbol>)
    c.report_error(
      <parse>, "symbol-set entries must be literal Symbols",
      token, %("use %<<foo bar>>"));
  String spelling = kind == <lit-symbol>
    ? _angle_spelling(token.text) : _member_spelling(token.text);
  return _exact_symbol(c, token, spelling);
}

/* A quoted member drops its quotes. */
static String _member_spelling(String text) {
  if (text && text[0] == '"')
    return String.new_len(text + 1, text.len() - 2).unescape();
  return text.unescape();
}

/** Builds a typed `SymbolSet` expression from source-ordered `Symbol` values.
    Stores the first duplicate index, or -1, through `duplicate`; a duplicate
    returns NULL.
*/
List Compiler.symbol_set_expression(Compiler c, List values, int &duplicate) {
  duplicate = _duplicate_index(values);
  if (duplicate >= 0) return NULL;
  Array symbols = values;
  List set = _set_expression(symbols);
  symbols.free();
  return set;
}

static int _duplicate_index(List values) {
  Map seen = {};
  int index = 0;
  foreach (Symbol value, values) {
    if (value in seen) return index;
    seen[value] = 1;
    index++;
  }
  return -1;
}

static List _set_expression(Array symbols) {
  $scope() {
    String text = _octal_literal(SymbolSet.encode(symbols));
    List bytes = %(expr (* char) (literal (* char) $text));
    List decl = %(decl ("SymbolSet") (bindings (bind () ())));
    return %(expr ("SymbolSet") (cast $decl $bytes));
  }
}

/* The bytes as octal escapes in one C string literal. */
static String _octal_literal(Block bytes) {
  unsigned char *data = bytes.bytes;
  Buffer output = Buffer.new(0);
  output.write("\"");
  for (size_t at = 0; at < bytes.len(); at++)
    output.printf("\\%03o", (unsigned) data[at]);
  output.write("\"");
  return output.str_free();
}

/* Arrays and Maps

   `%[...]` and `%{...}` read quoted elements. A Map entry, quoted or
   evaluated, may come from an entry-position macro, whose `(seq ...)` rows
   join the entries in source order. */

/** Parses a quoted Array literal into a typed, source-ordered `(array ...)`
    node and consumes its closing `]`.
*/
List Compiler.parse_array_literal(Compiler compiler) {
  compiler.expect(<"%[">);
  List elems = _parse_array_elements(compiler);
  compiler.expect(<"]">);
  return %(expr ("Array") (array @elems));
}

/* An Expr sequence hole fills one quoted Array argument position. */
static List _parse_array_element(Compiler c) {
  List slot = c.try_parse_macro_slot(<argument>);
  return slot ? slot : _parse_element(c);
}

/* A comma may follow the last element. */
static List _parse_array_elements(Compiler c) {
  if (c.peek(0) == <]>) return NULL;
  Array elements = [];
  elements.push(_parse_array_element(c));
  while (c.test(<,>) && c.peek(0) != <]>)
    elements.push(_parse_array_element(c));
  return elements.list_free();
}

/** Parses a quoted Map literal into a typed, source-ordered `(map ...)` node
    and consumes its closing `}`.
*/
List Compiler.parse_map_literal(Compiler compiler) {
  compiler.expect(<"%{">);
  List elems = _parse_quoted_entries(compiler);
  compiler.expect(<"}">);
  return %(expr ("Map") (map @elems));
}

static List _parse_quoted_entries(Compiler c) {
  Array entries = [];
  while (c.peek(0) != <"}">) {
    _push_entry(entries, _parse_quoted_entry(c));
    if (c.peek(0) == <"}">) break;
    c.expect(<,>);
  }
  return entries.list_free();
}

static void _push_entry(Array entries, Ast entry) {
  if (entry && entry.car() == <seq>)
    foreach (Var row, entry.cdr()) entries.push(row);
  else if (entry) entries.push(entry);
}

/* `${...}` holds a macro-produced entry or an expression key. */
static List _parse_quoted_entry(Compiler c) {
  Token origin = c.token;
  if (c.peek(0) != <"${"> || c.token.len != 2)
    return _entry_value(c, _parse_element(c), origin);
  c.next();
  List entry = c.try_parse_macro_slot(<map-entry>);
  if (!entry) entry = c.try_parse_macro_target_at(AST_MAP_ENTRY);
  if (entry) {
    c.expect(<"}">);
    return entry;
  }
  List key = c.parse_expression();
  c.expect(<"}">);
  return _entry_value(c, key, origin);
}

static List _entry_value(Compiler c, List key, Token origin) {
  c.expect(<:>);
  List value = _parse_element(c);
  return c.resolve_map_entry(%(map-entry $key $value), origin);
}

/** Parses comma-separated `Map` entries up to but not including `}`.
    `Entry`-position macro sequences are flattened in source order.
*/
List Compiler.parse_map_entries(Compiler c) {
  Array entries = [];
  while (c.peek(0) != <"}">) {
    _push_entry(entries, c.parse_map_entry());
    if (c.peek(0) == <"}">) break;
    c.expect(<,>);
  }
  return entries.list_free();
}

/** Parses one `Map` entry without consuming its following comma or `}`.
    A bare identifier key is an Atom; any other key is an expression.
    A direct row returns a resolved `(map-entry KEY VALUE)` node; an
    entry-position macro may return `(seq ...)` for its caller to splice.
*/
List Compiler.parse_map_entry(Compiler compiler) {
  List slot = compiler.try_parse_macro_slot(<map-entry>);
  if (slot) return slot;
  List macro = compiler.try_parse_macro_target_at(AST_MAP_ENTRY);
  if (macro) return macro;
  Token origin = compiler.token;
  List key = NULL;
  if (compiler.peek(0) == <ident> && compiler.peek(1) == <:>) {
    List literal = _atom_literal(compiler, compiler.token.text);
    compiler.next();
    key = %(expr ${literal.cadr()} $literal);
  }
  else key = compiler.parse_assignment();
  compiler.expect(<:>);
  List value = compiler.parse_assignment();
  return compiler.resolve_map_entry(%(map-entry $key $value), origin);
}

/* strings

   `%"..."` reads text segments and `$` insertions in source order. A text
   segment drops its line continuations, turns CR and CRLF into LF, and
   decodes escapes and `$$`. */

/** Parses a percent `String` literal and returns its typed expression after
    the closing quote. Static segments enter the compiler cache unless
    `runtime_literals` is set; interpolated segments remain source ordered.
*/
List Compiler.parse_string_literal(Compiler compiler) {
  compiler.expect(<"%\"">);
  if (compiler.test(<"\"">)) return %(expr ("String") (0));
  List segments = _parse_string_segments(compiler);
  compiler.expect(<"\"">);
  if (segments.match(%((cache *))))
    return %(expr ("String") ${segments.car()});
  return %(expr ("String") ${source_string_content(segments)});
}

static List _parse_string_segments(Compiler c) {
  Array segments = [];
  while (c.peek(0) != <"\"">) segments.push(_parse_string_segment(c));
  return segments.list_free();
}

static List _parse_string_segment(Compiler c) {
  switch (c.peek(0)) {
    case <segment>: return _parse_text_segment(c);
    case <$>:       return _parse_named_segment(c);
    case <"${">:    return _parse_braced_segment(c);
    default:
      c.report_error(<parse>, "expected string segment", c.token, NULL);
  }
}

static List _parse_text_segment(Compiler c) {
  String text = _decode_segment(c.token.text);
  if (c.runtime_literals) {
    c.next();
    return %(segexp (expr ("String") (literal ("String") $text)));
  }
  List cached =
    c.cache(%(string (expr ("String") (literal ("String") $text))));
  c.next();
  return cached;
}

static List _parse_named_segment(Compiler c) {
  List expr = _parse_named_reference(
    c, <$>, "use '${...}' to insert an expression");
  expr = c.convert_segment_to_string(expr);
  return %(segvar $expr);
}

static List _parse_braced_segment(Compiler c) {
  c.next();
  List expr = c.parse_expression();
  c.check_explicit_converter(expr, %("String"), 1);
  expr = c.convert_segment_to_string(expr);
  c.expect(<"}">);
  return %(segexp $expr);
}

static String _decode_segment(String raw) {
  if (!raw) return "";
  return _normalize_newlines(raw).unescape().replace("$$", "$");
}

/* Text with no line continuation and no CR returns unchanged. */
static String _normalize_newlines(String raw) {
  int n = raw.len(), char *buf = Scope.malloc(n + 1);
  int dst = 0, changed = 0, i = 0;
  while (i < n) {
    char ch = raw[i];
    int skip = ch == '\\' ? _continuation(raw, i, n) : 0;
    if (skip) {
      changed = 1;
      i += skip;
    }
    else if (ch == '\r') {
      changed = 1;
      buf[dst++] = '\n';
      i++;
      if (i < n && raw[i] == '\n') i++;
    }
    else {
      buf[dst++] = ch;
      i++;
    }
  }
  String normalized = changed ? String.new_len(buf, dst) : raw;
  Scope.free(buf);
  return normalized;
}

/* The length of the line continuation at the backslash at `i`: 2 before
   LF, 3 before CRLF, and 0 otherwise. */
static int _continuation(String raw, int i, int n) {
  if (i + 1 >= n) return 0;
  if (raw[i + 1] == '\n') return 2;
  return raw[i + 1] == '\r' && i + 2 < n && raw[i + 2] == '\n' ? 3 : 0;
}

// atoms and Symbols

/** Parses the current atomic token into a typed expression and advances once.
    Pattern and macro-hole state control binder validation and quoting, while
    shallow parsing permits provisional numeric types.
*/
List Compiler.parse_atomic_literal(Compiler c) {
  String text = c.token.text, List literal = NULL;
  switch (c.peek(0)) {
    case <void>:
      literal = source_literal_content(%(("Var") "void"));
      break;
    case <lit-char>:
      literal = source_literal_content(%((char) $text));
      break;
    case <lit-int>:    literal = _number_literal(c, text, 0); break;
    case <lit-float>:  literal = _number_literal(c, text, 1); break;
    case <lit-char*>:
      literal = source_literal_content(%((* char) $text));
      break;
    case <lit-atom>:   literal = _atom_literal(c, text);      break;
    case <lit-symbol>: literal = _symbol_literal(c, text);    break;
  }
  if (literal) {
    c.next();
    return %(expr ${literal.cadr()} $literal);
  }
  Symbol kind = c.peek(0);
  c.report_error(
    <parse>, "expected atomic expression", c.token,
    %( "token:" ${c.token.text} "kind:" ${kind.str()} ));
}

/* Shallow declaration discovery gives a number outside every supported
   scalar type a provisional type. */
static List _number_literal(Compiler c, String text, int floating) {
  Type type = Type.numeric_literal(text, floating);
  if (!type && c.shallow) type = floating ? %(double) : %(int);
  if (!type)
    c.report_error(
      <type>, "numeric literal is outside the supported scalar range",
      c.token, %( "literal:" $text ));
  return %(literal $type $text);
}

/* A bare spelling names an Atom, which is a compact Symbol when it fits. */
static List _atom_literal(Compiler c, String text) {
  String spelling = text.unescape(), Atom atom = Atom.intern(spelling);
  _check_binder(c, atom);
  if (spelling in c.object_macros) _warn_macro_name(c, spelling);
  if (atom is <symbol>) return %(literal ("Symbol") $text ${atom.symbol()});
  Var value = c.macro_holes && atom.is_binder() ? %(!quote $atom) : atom;
  return %(literal ("Atom") $spelling $value);
}

/* In a pattern, a spelling that starts with `?` or `*` must be a binder
   name, except that `?binder?` and `*binder?` may end an `!is` form. */
static void _check_binder(Compiler c, Atom atom) {
  if (!c.in_pattern || !atom.is_atom()) return;
  char first = atom.first();
  if ((first != '?' && first != '*') || atom.is_binder()) return;
  int reserved = atom == <?binder?> || atom == <*binder?>;
  if (reserved && c.match_is && c.peek(1) == <)>) return;
  c.report_error(
    <parse>, "invalid match binder name",
    c.token, %( "binder-name:" ${atom.str()} ));
}

/* The preprocessor never sees a literal, so a macro's name here is data.
   The author who wanted its value must unquote it. */
static void _warn_macro_name(Compiler c, String spelling) {
  String unquoted = "${(long) " + spelling + "}";
  c.report_warning(
    <literal>,
    %"'$spelling' is a Symbol here; unquote a typed value such as "
      + %"$unquoted to insert the macro's value",
    c.token, NULL);
}

/* A `<...>` literal is an exact Symbol, which a pattern may use as a
   binder. */
static List _symbol_literal(Compiler c, String text) {
  Symbol symbol = _exact_symbol(c, c.token, _angle_spelling(text));
  _check_binder(c, symbol);
  return %(literal ("Symbol") $text $symbol);
}

/* The angle brackets are not part of a Symbol's value, nor are the quotes
   of a quoted spelling such as `<"a b">`. */
static String _angle_spelling(String text) {
  int len = text.len();
  if (len >= 4 && text[1] == '"')
    return String.new_len(text + 2, len - 4).unescape();
  return String.new_len(text + 1, len - 2);
}

/* A compact Symbol literal must decode to its source spelling. */
static Symbol _exact_symbol(Compiler c, Token token, String spelling) {
  Symbol symbol;
  if (Symbol.try_new(spelling, &symbol)) return symbol;
  Symbol lossy = spelling ? Symbol.new(spelling) : 0;
  c.report_error(
    <parse>, "Symbol literal does not round-trip", token,
    %("source spelling: $spelling" "encoded spelling: ${lossy}"));
}
