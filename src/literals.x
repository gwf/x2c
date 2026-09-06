/*  literals.x -- x2c literal and lambda parsing

    Parses `List`, `Array`, `Map`, interpolated `String`, and lambda literals.
    Stable
    `List` cells and `String` segments are cached only when they contain no
    dynamic references. Lambda bodies are expressions or blocks;
    parameters may use typed declarations or bare identifiers, and lexical
    automatic values are recorded for captured `Func` lowering.
  */
#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#pragma private
#include "parse.x"
#include "type.x"
#include "expressions.x"
#include "lambda.x"
#include <stdint.h>
#include <string.h>

// literals

static List _parse_named_reference(
  Compiler compiler, Symbol sigil, String hint) {
  compiler.expect(sigil);
  if (compiler.peek(0) != <ident>) {
    String message = %"expected identifier after '$sigil'";
    compiler.report_error(<parse>, message, compiler.token, %( $hint ));
  }
  return compiler.parse_variable();
}

// list literal parsing
static List _parse_splice_element(Compiler compiler) {
  if (compiler.peek(0) == <@>) {
    List expr = _parse_named_reference(
      compiler, <@>, "use '@{...}' to splice an expression");
    return %(splice $expr);
  }
  if (!compiler.test(<"@{">)) return NULL;
  List expr = compiler.parse_expression();
  compiler.expect(<"}">);
  return %(splice $expr);
}

static List _parse_variable_reference(Compiler compiler) {
  if (compiler.peek(0) == <$>)
    return _parse_named_reference(
      compiler, <$>, %"use '\${...}' to insert an expression");
  if (compiler.peek(0) != <"${"> || compiler.token.len != 2)
    return NULL;
  compiler.next();
  List expr = compiler.parse_expression();
  compiler.expect(<"}">);
  return expr;
}

static List _parse_literal_element(Compiler compiler) {
  switch (compiler.peek(0)) {
    case <"(">:      return compiler.parse_list_literal();
    case <"%\"">:    return compiler.parse_string_literal();
    case <"%[">:     return compiler.parse_array_literal();
    case <"%{">:     return compiler.parse_map_literal();
    default:         return compiler.parse_atomic_literal();
  }
}

static List _parse_collection_element(Compiler compiler) {
  List reference = _parse_variable_reference(compiler);
  return reference ? reference : _parse_literal_element(compiler);
}

static List _build_cons_cell(Compiler compiler, List head, List tail) {
  match (head) {
    case %(!or (splice ?sexpr) (expr ("List") (splice ?sexpr))): {
      head = Var.list(sexpr);
      if (compiler.sym.is_var_type(head.cadr()))
        head = %(expr ("List") (call "Var_list" (args $head)));
      else head = compiler.convert_expression(head, %("List"));
      return %(expr ("List") (append $head $tail) );
    }
  }
  if (head.match(%(expr (<macro-expr>) ?)))
    return %(expr ("List") (cons $head $tail));
  head = compiler.convert_expression(head, %("Var"));
  List cached = compiler.cache_cons_cell(head, tail);
  if (cached) return cached;
  return %(expr ("List") (cons $head $tail));
}

/* Decode the source spelling of a compact Symbol literal. Angle literals
   and quoted symbol-set entries carry delimiters that are not part of the
   value; the other literal paths provide bare Atom text. */
static String _symbol_source_spelling(String text, int angle) {
  if (angle) {
    int len = text.len();
    if (len >= 4 && text[1] == '"')
      return String.new_len(text + 2, len - 4).unescape();
    return String.new_len(text + 1, len - 2);
  }
  if (text && text[0] == '"')
    return String.new_len(text + 1, text.len() - 2).unescape();
  return text.unescape();
}

static Symbol _exact_symbol_literal(
  Compiler compiler, Token token, String spelling) {
  Symbol symbol;
  if (!Symbol.try_new(spelling, &symbol)) {
    Symbol lossy = spelling ? Symbol.new(spelling) : 0;
    compiler.report_error(
      <parse>, "Symbol literal does not round-trip", token,
      %("source spelling: $spelling"
        "encoded spelling: ${lossy.str()}")
    );
  }
  return symbol;
}

static List _list_prefix_atom(Compiler compiler, String spelling) {
  Atom atom = Atom.intern(spelling);
  List literal = atom is <symbol>
    ? %(literal ("Symbol") $spelling ${atom.symbol()})
    : %(literal ("Atom") $spelling $atom);
  List expression = %(expr ${literal.cadr()} $literal);
  if (compiler.runtime_literals) return expression;
  return compiler.cache(%(var $expression));
}

static List _parse_list_reader_prefix(Compiler compiler) {
  String spelling = NULL;
  switch (compiler.peek(0)) {
    case <"'">:  spelling = "quote";            break;
    case <"`">:  spelling = "quasiquote";       break;
    case <",">:  spelling = "unquote";          break;
    case <",@">: spelling = "unquote-splicing"; break;
    default: return NULL;
  }
  compiler.next();
  List value = _parse_list_head(compiler);
  List tail = _build_cons_cell(compiler, value, %(nil));
  return _build_cons_cell(
    compiler, _list_prefix_atom(compiler, spelling), tail);
}

static int _match_is_head(Compiler compiler) {
  if (!compiler.in_pattern) return 0;
  if (compiler.peek(0) == <lit-atom>)
    return Atom.intern(compiler.token.text.unescape()) == <!is>;
  if (compiler.peek(0) == <lit-symbol>) {
    Token token = compiler.token;
    String spelling = _symbol_source_spelling(token.text, 1);
    Symbol symbol = _exact_symbol_literal(compiler, token, spelling);
    return symbol == <!is>;
  }
  return 0;
}

static List _parse_list_head(Compiler compiler) {
  List elem = NULL;
  if ((elem = _parse_list_reader_prefix(compiler))) return elem;
  if ((elem = _parse_splice_element(compiler))) return %(expr ("List") $elem);
  if ((elem = _parse_variable_reference(compiler))) return elem;
  elem = _parse_literal_element(compiler);
  Var matched;
  List bindings;
  /* A reference is `(ident <binding-list>)`. The binding sublist has to be
     part of the search: `%(ident *)` also matches the final cell of a
     literal node ending in the Symbol <ident>. */
  if (elem.try_search(%(ident (*)), &matched, &bindings)) return elem;
  if (compiler.runtime_literals) return elem;
  return compiler.cache(%(var $elem));
}

static List _parse_list_tail(Compiler compiler) {
  if (compiler.peek(0) == <)>) return %(nil);
  List head = _parse_list_head(compiler), tail = _parse_list_tail(compiler);
  return _build_cons_cell(compiler, head, tail);
}

/** Parses a `List` literal beginning at `(` or `%(` and returns its typed
    expression after consuming `)`. Pattern parsing sets and restores
    `match_is`; `runtime_literals` disables stable-cell caching.
*/
List Compiler.parse_list_literal(Compiler c) {
  int runtime_literal = c.peek(0) == <"%(">;
  c.next();
  if (c.test(<)>)) return %(expr ("List") (nil));
  int old_match_is = c.match_is;
  c.match_is = _match_is_head(c);
  List reader_form = runtime_literal
    ? _parse_list_reader_prefix(c)
    : NULL;
  if (reader_form && c.test(<)>)) {
    c.match_is = old_match_is;
    return reader_form;
  }
  List head = reader_form ? reader_form : _parse_list_head(c);
  List tail = _parse_list_tail(c);
  c.expect(<)>);
  c.match_is = old_match_is;
  return %(expr ("List") ${_build_cons_cell(c, head, tail)});
}

// Symbol-set literal generation

typedef struct SymbolSetEdge {
  uint32_t vertices[3];
} SymbolSetEdge;

static uint64_t _symbol_set_literal_mix(uint64_t value) {
  value ^= value >> 30;
  value *= UINT64_C(0xbf58476d1ce4e5b9);
  value ^= value >> 27;
  value *= UINT64_C(0x94d049bb133111eb);
  return value ^ (value >> 31);
}

static void _symbol_set_vertices(
  SymbolSetEdge *edge, Symbol symbol, uint64_t seed, uint32_t span) {
  uint64_t hash = _symbol_set_literal_mix((uint64_t) symbol ^ seed);
  uint32_t mask = span - 1;
  edge.vertices[0] = (uint32_t) hash & mask;
  edge.vertices[1] = span + ((uint32_t) (hash >> 21) & mask);
  edge.vertices[2] = span * 2 + ((uint32_t) (hash >> 42) & mask);
}

static int _build_symbol_set_hash(
  Array symbols, uint32_t span, uint64_t seed, uint32_t *table) {
  int count = (int) symbols.len(), vertices = (int) span * 3;
  SymbolSetEdge *edges = Scope.calloc(count, sizeof(SymbolSetEdge));
  int *degree = Scope.calloc(vertices, sizeof(int));
  int *edge_xor = Scope.calloc(vertices, sizeof(int));
  int *queue = Scope.calloc(vertices, sizeof(int));
  int *order_edges = Scope.calloc(count, sizeof(int));
  int *order_vertices = Scope.calloc(count, sizeof(int));
  unsigned char *removed = Scope.calloc(count, 1);
  for (int edge = 0; edge < count; edge++) {
    _symbol_set_vertices(edges + edge, symbols[edge], seed, span);
    for (int part = 0; part < 3; part++) {
      uint32_t vertex = edges[edge].vertices[part];
      degree[vertex]++;
      edge_xor[vertex] ^= edge;
    }
  }
  int head = 0, tail = 0;
  for (int vertex = 0; vertex < vertices; vertex++)
    if (degree[vertex] == 1) queue[tail++] = vertex;
  int ordered = 0;
  while (head < tail) {
    int vertex = queue[head++];
    if (degree[vertex] != 1) continue;
    int edge = edge_xor[vertex];
    if (removed[edge]) continue;
    removed[edge] = 1;
    order_edges[ordered] = edge;
    order_vertices[ordered++] = vertex;
    for (int part = 0; part < 3; part++) {
      uint32_t adjacent = edges[edge].vertices[part];
      degree[adjacent]--;
      edge_xor[adjacent] ^= edge;
      if (degree[adjacent] == 1) queue[tail++] = adjacent;
    }
  }
  if (ordered != count) return 0;
  for (int position = count - 1; position >= 0; position--) {
    int edge = order_edges[position], vertex = order_vertices[position];
    uint32_t value = (uint32_t) edge;
    for (int part = 0; part < 3; part++) {
      uint32_t adjacent = edges[edge].vertices[part];
      if ((int) adjacent != vertex) value ^= table[adjacent];
    }
    table[vertex] = value;
  }
  return 1;
}

static Buffer _write_symbol_set_word(
  Buffer output, uint64_t value, int bytes) {
  for (int byte = 0; byte < bytes; byte++) {
    output.printf("\\%03o", (unsigned) (value & 0xff));
    value >>= 8;
  }
  return output;
}

static int _symbol_set_duplicate(List values) {
  Map seen = %{};
  int index = 0;
  foreach (Symbol value, values) {
    if (seen.contains(value)) return index;
    seen[value] = 1;
    index++;
  }
  return -1;
}

static List _symbol_set_literal_expression(Array symbols) {
  int count = (int) symbols.len(), uint32_t span = 1;
  while ((uint64_t) span * 3 < (uint64_t) count * 3 / 2) span <<= 1;
  int width = count <= 0x100 ? 1 : count <= 0x10000 ? 2 : 4, vertices = 0;
  uint32_t *table = NULL, uint64_t seed = 0, int built = count == 0;
  while (!built) {
    vertices = (int) span * 3;
    table = Scope.calloc(vertices, sizeof(uint32_t));
    for (uint64_t attempt = 0; !built && attempt < 4096; attempt++) {
      memset(table, 0, (size_t) vertices * sizeof(uint32_t));
      seed = UINT64_C(0x9e3779b97f4a7c15) +
             attempt * UINT64_C(0xd1b54a32d192ed03);
      built = _build_symbol_set_hash(symbols, span, seed, table);
    }
    if (!built) span <<= 1;
  }
  Buffer output = Buffer.new(0);
  output.write("\"");
  _write_symbol_set_word(output, width, 1);
  _write_symbol_set_word(output, 0, 3);
  _write_symbol_set_word(output, count, 4);
  _write_symbol_set_word(output, span - 1, 4);
  _write_symbol_set_word(output, seed, 8);
  for (int vertex = 0; vertex < vertices; vertex++)
    _write_symbol_set_word(output, table[vertex], width);
  for (int index = 0; index < count; index++)
    _write_symbol_set_word(output, symbols[index].symbol(), 8);
  output.write("\"");
  String text = output.str_free();
  List bytes = %(expr (* char) (literal (* char) $text));
  List decl = %(decl ("SymbolSet") (bindings (bind () ())));
  return %(expr ("SymbolSet") (cast $decl $bytes));
}

/** Builds a typed `SymbolSet` expression from source-ordered `Symbol` values.
    Stores the first duplicate index, or -1, through `duplicate`; a duplicate
    returns NULL.
*/
List Compiler.symbol_set_expression(
  Compiler compiler, List values, int *duplicate) {
  int repeated = _symbol_set_duplicate(values);
  *duplicate = repeated;
  if (repeated >= 0) return NULL;
  Array symbols = values;
  List result = _symbol_set_literal_expression(symbols);
  symbols.free();
  return result;
}

/** Parses a `%<<...>>` literal into an immutable ordered `SymbolSet`.
    Entries must be literal compact `Symbol`s; source order defines dense
    indexes
    and an equal encoded `Symbol` reports a duplicate diagnostic.
*/
List Compiler.parse_symbol_set_literal(Compiler c) {
  c.expect(<"%<<">);
  Array symbols = %[], tokens = %[];
  while (c.peek(0) != <">>">) {
    Token token = c.token;
    Symbol kind = c.peek(0);
    if (kind != <lit-atom> && kind != <lit-symbol>)
      c.report_error(
        <parse>, "symbol-set entries must be literal Symbols",
        token, %("use %<<foo bar>>"));
    int angle = kind == <lit-symbol>;
    String spelling = _symbol_source_spelling(token.text, angle);
    Symbol symbol = _exact_symbol_literal(c, token, spelling);
    symbols.push(symbol);
    tokens.push(token);
    c.next();
  }
  c.expect(<">>">);
  int duplicate = -1;
  List result = c.symbol_set_expression(symbols, &duplicate);
  if (duplicate >= 0) {
    Token token = tokens[duplicate];
    Symbol symbol = symbols[duplicate];
    c.report_error(
      <parse>, "duplicate Symbol in symbol set", token,
      %("symbol:" ${symbol.repr()}));
  }
  symbols.free();
  tokens.free();
  return result;
}

static List _parse_error_symbol(
  Compiler compiler, String owner, String role, String hint) {
  Token token = compiler.token;
  if (compiler.peek(0) != <lit-atom>)
    compiler.report_error(
      <parse>, %"$owner $role must be a bare Symbol",
      token, %($hint));
  String text = token.text.unescape();
  Symbol symbol = _exact_symbol_literal(compiler, token, text);
  compiler.next();
  return %(expr ("Symbol") (literal ("Symbol") $text $symbol));
}

/** Parses the `%()` payload following `raise` into a `(raise CODE (args ...))`
    node and consumes its closing `)`. The code and detail keys must be bare
    `Symbol`s, each keyed detail has one value, and payload literals bypass the
    compiler cache.
*/
List Compiler.parse_raise_literal(Compiler c) {
  c.expect(<"%(">);
  int old_runtime = c.runtime_literals;
  c.runtime_literals = 1;
  List code = _parse_error_symbol(
    c, "raise", "code", "use raise %(code (key value)...);");

  Array args = %[];
  while (c.peek(0) != <)>) {
    Token pair_token = c.token;
    c.expect(
      <(>);
    List key = _parse_error_symbol(
      c, "raise", "detail key",
      "use raise %(code (key value)...);");
    if (c.peek(0) == <)>)
      c.report_error(
        <parse>, "raise detail requires exactly one value",
        pair_token, NULL);
    List value = _parse_list_head(c);
    if (value.match(%(expr ("List") (splice *))) || value.match(%(splice *)))
      c.report_error(
        <parse>, "raise detail value cannot splice",
        pair_token, %("pass one value expression"));
    if (c.peek(0) != <)>)
      c.report_error(
        <parse>, "raise detail requires exactly one value",
        pair_token, NULL);
    c.expect(<)>);
    args.push(key);
    args.push(value);
  }
  c.expect(<)>);
  List values = args;
  args.free();
  c.runtime_literals = old_runtime;
  return %(raise $code (args @values));
}

static List _build_error_pattern_list(Compiler compiler, Array values) {
  List result = %(nil);
  for (int i = values.len() - 1; i >= 0; i--)
    result = _build_cons_cell(compiler, values[i], result);
  return %(expr ("List") $result);
}

/** Parses a filtered-catch `%()` payload into a typed `List` pattern.
    The call consumes the closing `)`. A bare code `Symbol` may be followed by
    `*` patterns or `(key pattern)` pairs; pattern and runtime-literal state is
    restored on success.
*/
List Compiler.parse_catch_pattern_literal(Compiler c) {
  c.expect(<"%(">);
  int previous = c.in_pattern, old_runtime = c.runtime_literals;
  c.in_pattern = 1;
  c.runtime_literals = 1;
  List code = _parse_error_symbol(
    c, "catch filter", "code",
    "use catch %(code (key pattern)...):");

  Array elements = %[];
  elements.push(code);
  while (c.peek(0) != <)>) {
    Token detail_token = c.token;
    if (c.peek(0) == <lit-atom> &&
        c.token.text.unescape()[0] == '*') {
      elements.push(_parse_list_head(c));
      continue;
    }
    if (!c.test(<(>))
      c.report_error(
        <parse>, "catch filter detail must be '*' or '(key pattern)'",
        detail_token, %("wrap keyed detail patterns in parentheses"));
    List key = _parse_error_symbol(
      c, "catch filter", "detail key",
      "use catch %(code (key pattern)...):");
    if (c.peek(0) == <)>)
      c.report_error(
        <parse>, "catch filter detail requires exactly one pattern",
        detail_token, NULL);
    List value = _parse_list_head(c);
    if (value.match(%(expr ("List") (splice *))) || value.match(%(splice *)))
      c.report_error(
        <parse>, "catch filter detail pattern cannot splice",
        detail_token, %("write one match pattern"));
    if (c.peek(0) != <)>)
      c.report_error(
        <parse>, "catch filter detail requires exactly one pattern",
        detail_token, NULL);
    c.expect(<)>);
    Array pair = %[];
    pair.push(key);
    pair.push(value);
    elements.push(_build_error_pattern_list(c, pair));
    pair.free();
  }
  c.expect(<)>);
  List result = _build_error_pattern_list(c, elements);
  elements.free();
  c.in_pattern = previous;
  c.runtime_literals = old_runtime;
  return result;
}

static List _parse_quoted_array_elements(Compiler compiler) {
  if (compiler.peek(0) == <]>) return NULL;
  Array values = %[];
  values.push(_parse_collection_element(compiler));
  while (compiler.test(<,>)) {
    if (compiler.peek(0) == <]>) break;
    values.push(_parse_collection_element(compiler));
  }
  return values.list_free();
}

/** Parses a quoted Array literal into a typed, source-ordered `(array ...)`
    node and consumes its closing `]`.
*/
List Compiler.parse_array_literal(Compiler compiler) {
  compiler.expect(<"%[">);
  List elems = _parse_quoted_array_elements(compiler);
  compiler.expect(<"]">);
  return %(expr ("Array") (array @elems));
}

/** Parses one `Map` entry without consuming its following comma or `}`.
    A direct row returns a resolved `(map-entry KEY VALUE)` node; an
    entry-position macro may return `(seq ...)` for its caller to splice.
*/
List Compiler.parse_map_entry(Compiler compiler) {
  List slot = compiler.try_parse_macro_slot(<map-entry>);
  if (slot) return slot;
  int macro_follows =
    (compiler.peek(0) == <$> &&
     compiler.macro_starts_target_at(AST_MAP_ENTRY)) ||
    (compiler.peek(0) == <ident> &&
     compiler.keyword_alias_starts_target_at(AST_MAP_ENTRY));
  List macro = macro_follows
    ? compiler.try_parse_macro_target_at(AST_MAP_ENTRY) : NULL;
  if (macro) return macro;
  Token origin = compiler.token;
  List key = compiler.parse_assignment();
  compiler.expect(<:>);
  List value = compiler.parse_assignment();
  return compiler.resolve_map_entry(%(map-entry $key $value), origin);
}

/** Parses comma-separated `Map` entries up to but not including `}`.
    `Entry`-position macro sequences are flattened in source order.
*/
List Compiler.parse_map_entries(Compiler c) {
  Array values = %[];
  while (c.peek(0) != <"}">) {
    Ast insertion = c.parse_map_entry();
    if (insertion && insertion.car() == <seq>)
      foreach (Var row, insertion.cdr()) values.push(row);
    else if (insertion) values.push(insertion);
    if (c.peek(0) == <"}">) break;
    c.expect(<,>);
  }
  return values.list_free();
}

static List _parse_quoted_map_entry(Compiler c) {
  Token origin = c.token;
  if (c.peek(0) == <"${"> && c.token.len == 2) {
    c.next();
    List insertion = c.try_parse_macro_slot(<map-entry>);
    if (!insertion) {
      int macro_follows =
        (c.peek(0) == <$> && c.macro_starts_target_at(AST_MAP_ENTRY)) ||
        (c.peek(0) == <ident> &&
         c.keyword_alias_starts_target_at(AST_MAP_ENTRY));
      if (macro_follows) insertion = c.try_parse_macro_target_at(AST_MAP_ENTRY);
    }
    if (insertion) {
      c.expect(<"}">);
      return insertion;
    }
    List key = c.parse_expression();
    c.expect(<"}">);
    c.expect(<:>);
    List value = _parse_collection_element(c);
    return c.resolve_map_entry(%(map-entry $key $value), origin);
  }
  List key = _parse_collection_element(c);
  c.expect(<:>);
  List value = _parse_collection_element(c);
  return c.resolve_map_entry(%(map-entry $key $value), origin);
}

static List _parse_quoted_map_entries(Compiler c) {
  Array values = %[];
  while (c.peek(0) != <"}">) {
    Ast insertion = _parse_quoted_map_entry(c);
    if (insertion && insertion.car() == <seq>)
      foreach (Var row, insertion.cdr()) values.push(row);
    else if (insertion) values.push(insertion);
    if (c.peek(0) == <"}">) break;
    c.expect(<,>);
  }
  return values.list_free();
}

/** Parses a quoted Map literal into a typed, source-ordered `(map ...)` node
    and consumes its closing `}`.
*/
List Compiler.parse_map_literal(Compiler compiler) {
  compiler.expect(<"%{">);
  List elems = _parse_quoted_map_entries(compiler);
  compiler.expect(<"}">);
  return %(expr ("Map") (map @elems));
}

// Normalize embedded newlines so they survive parsing and remove
// line-continuation backslash-newline pairs (including CRLF).
static String _normalize_multiline_string(String raw) {
  if (!raw) return "";
  int n = raw.len(), char *buf = Scope.malloc(n + 1);
  int dst = 0, changed = 0, i = 0;
  while (i < n) {
    char ch = raw[i];
    if (ch == '\\' && i + 1 < n) {
      if (raw[i + 1] == '\n') {
        changed = 1;
        i += 2;
        continue;
      }
      if (raw[i + 1] == '\r' && i + 2 < n && raw[i + 2] == '\n') {
        changed = 1;
        i += 3;
        continue;
      }
    }
    if (ch == '\r') {
      changed = 1;
      if (i + 1 < n && raw[i + 1] == '\n') i += 2;
      else i++;
      buf[dst++] = '\n';
      continue;
    }
    if (ch == '\n') {
      buf[dst++] = '\n';
      i++;
      continue;
    }
    buf[dst++] = ch;
    i++;
  }
  if (!changed) {
    Scope.free(buf);
    return raw;
  }
  buf[dst] = '\0';
  String normalized = String.new_len(buf, dst);
  Scope.free(buf);
  return normalized;
}

static String _decode_string_segment_text(String raw) {
  if (!raw) return "";
  return _normalize_multiline_string(raw).unescape().replace("$$", "$");
}

static List _parse_string_segment(Compiler c) {
  List sgmnt, expr, String str = NULL;
  switch (c.peek(0)) {
    case <segment>: str = _decode_string_segment_text(c.token.text);
      if (c.runtime_literals) {
        c.next();
        return %(segexp (expr ("String") (literal ("String") $str)));
      }
      sgmnt = %(string (expr ("String") (literal ("String") $str)));
      sgmnt = c.cache(sgmnt);
      c.next();
      return sgmnt;
    case <$>:
      expr = _parse_named_reference(
        c, <$>, %"use '\${...}' to insert an expression");
      expr = c.convert_segment_to_string(expr);
      return %(segvar $expr);
    case <"${">:
      c.next();
      expr = c.parse_expression();
      expr = c.convert_segment_to_string(expr);
      c.expect(<"}">);
      return %(segexp $expr);
    default:
      c.report_error(<parse>, "expected string segment", c.token, NULL);
  }
}

static List _parse_string_segments(Compiler compiler) {
  Array segments = %[];
  while (compiler.peek(0) != <"\"">)
    segments.push(_parse_string_segment(compiler));
  List result = segments.list_free();
  return result;
}

/** Parses a percent `String` literal and returns its typed
    expression after the
    closing quote. Static segments enter the compiler cache unless
    `runtime_literals` is set; interpolated segments remain source ordered.
*/
List Compiler.parse_string_literal(Compiler compiler) {
  compiler.expect(<"%\"">);
  if (compiler.test(<"\"">)) return %(expr ("String") (0));
  List segments = _parse_string_segments(compiler);
  compiler.expect(<"\"">);
  if (segments.match(%((cache *)))) return %(expr ("String") ${car(segments)});
  return %(expr ("String") (segments @segments));
}

static int _lambda_looks_typed(Compiler compiler) {
  Symbol head = compiler.peek(0);
  if (head.is_builtin_type() || head.is_type_qualifier() ||
      head == <struct> || head == <union> || head == <enum> || head == <void>)
    return 1;
  if (head == <ident>) {
    String folded = compiler.package_alias_spelling();
    if (!folded)
      folded = compiler.package_member_spelling(compiler.token.text);
    String nm = folded ? folded : compiler.token.text;
    if (compiler.sym.get(%($nm)).type().is_typedef()) return 1;
  }
  return 0;
}

static void _lambda_expect_arrow(Compiler compiler) {
  compiler.expect(<"=">);
  compiler.expect(<">">);
}

static List _lambda_parse_typed_params(Compiler compiler, List *out_names) {
  Array names = %[], List typed_params = compiler.parse_parameter_list();
  foreach (List param, typed_params)
    match (param) {
      case %(param ? (bind ?binding ?)): {
        names.push(binding);
        compiler.semantic_binding_facts()[%(lambda-param $binding)] = 1;
      }
    }
  List result = names.list_free();
  if (out_names) *out_names = result;
  return typed_params;
}

static List _lambda_parse_bare_params(Compiler compiler) {
  Array names = %[];
  loop {
    if (compiler.peek(0) != <ident>)
      compiler.report_error(
        <parse>, "expected identifier in parameter list",
        compiler.token, NULL);
    String pname = compiler.token.text;
    List binding = compiler.sym.define(%($pname), %("Var"));
    names.push(binding);
    compiler.semantic_binding_facts()[%(lambda-param $binding)] = 1;
    compiler.semantic_binding_facts()[%(automatic $binding)] = 1;
    compiler.semantic_binding_facts()[%(type $binding)] = %("Var");
    compiler.next();
    if (!compiler.test(<,>)) break;
  }
  List result = names.list_free();
  return result;
}

// Build the function parameter types while retaining typed declarators.
static List _lambda_param_types_for_signature(
  Compiler compiler, List entries) {
  if (!entries) return %((void));
  Array types = %[];
  foreach (List entry, entries)
    match (entry) {
      case %(binding ? ?): types.push(%("Var"));
      case %(param ? ?): {
        Type type = entry.type_from_ast().declared();
        if (type.car() == <&>)
          type = cons(
            <&>, compiler.sym.normalize_declared_type(type.cdr()));
        types.push(type);
      }
    }
  return types.list_free();
}

static List _lambda_params_node(
  List names, List typed_params, int used_typed) =>
    used_typed ? %( params @typed_params ) : %( params @names );

static int _lambda_binding_is_outer(
  Compiler c, List binding, int depth) {
  Var captured_depth;
  Map facts = c.semantic_binding_facts();
  if (facts.try_get(%(lambda-depth $binding), &captured_depth))
    return captured_depth.integer() < depth;
  return facts.contains(%(automatic $binding)) &&
         c.sym.binding_is_local_before(binding, depth);
}

/** Reports whether the active lambda still needs to capture a binding. */
int Compiler.lambda_capture_required(Compiler c, List binding) {
  match (c.lambda_scopes)
    case %((lambda-scope ? ?depth ? ?supplied) *): {
      foreach (List row, supplied.list())
        match (row) case %(capture ?target ? ?):
          if (target == binding) return 1;
      return _lambda_binding_is_outer(c, binding, depth.integer());
    }
  return 0;
}

/** Opens lexical capture resolution while a lambda body is parsed or bound.
    `references` names explicitly shared surrounding bindings; `supplied`
    contains canonical capture rows supplied by constructed syntax. Evolving
    rows live in semantic binding facts so macro transactions restore them.
*/
void Compiler.begin_lambda_captures(
  Compiler c, List references, List supplied) {
  List scope = c.sym.introduce(c.fresh_name("lambda_scope"));
  int depth = c.sym.scope_count();
  c.lambda_scopes = cons(
    %(lambda-scope $scope $depth $references $supplied), c.lambda_scopes);
}

/** Finishes the active lambda's captures in first-use order. */
List Compiler.end_lambda_captures(Compiler c) {
  List rows = NULL;
  match (c.lambda_scopes.car())
    case %(lambda-scope ?scope ? ? ?): {
      Var stored;
      if (c.semantic_binding_facts().try_get(
            %(lambda-order $scope), &stored)) rows = stored;
    }
  c.lambda_scopes = c.lambda_scopes.cdr();
  return rows.reverse();
}

/** Resolves an automatic identifier through each enclosing lambda's captures.
    Fresh captured bindings keep sibling snapshots independent of shared-cell
    rewriting. Reference captures preserve qualifiers; snapshots of reference
    parameters copy their current referents.
*/
List Compiler.capture_lambda_identifier(
  Compiler c, List binding, Type type) {
  List original = binding;
  foreach (List frame, c.lambda_scopes.reverse())
    match (frame)
      case %(lambda-scope ?scope ?depth ?references ?supplied): {
        List prescribed = NULL;
        foreach (List row, supplied.list())
          match (row)
            case %(capture ?target ? ?):
              if (target == binding || target == original) prescribed = row;
        if (!prescribed &&
            !_lambda_binding_is_outer(c, binding, depth.integer())) continue;
        if (type.is_static()) continue;
        Map facts = c.semantic_binding_facts();
        List key = %(lambda-capture $scope $binding);
        Var stored;
        List row = NULL;
        if (facts.try_get(key, &stored)) row = stored;
        else {
          Type captured_type = type.car() == <&> ? type.cdr() : type;
          List expression = %(expr $type (ident $binding));
          int reference = references.list().contains(original);
          if (prescribed) {
            match (prescribed)
              case %(capture ? ?target_type ?value): {
                captured_type = target_type;
                List previous = c.lambda_scopes;
                while (c.lambda_scopes.car() != frame)
                  c.lambda_scopes = c.lambda_scopes.cdr();
                c.lambda_scopes = c.lambda_scopes.cdr();
                {
                  defer c.lambda_scopes = previous;
                  expression = c.resolve_expression(value, c.token);
                }
                reference = captured_type.car() == <&>;
              }
          }
          else if (reference) {
            captured_type = cons(<&>, captured_type);
            if (type.car() != <&>)
              expression = %(expr $captured_type (op & $expression));
          }
          else if (type.car() == <&>)
            expression = %(expr $captured_type (op * $expression));
          if (reference && facts.contains(%(lambda-snapshot $binding)))
            c.report_error(
              <type>,
              "reference capture requires an enclosing reference capture",
              c.token, %("binding: ${binding_identity_spelling(original)}"));
          List captured = c.sym.introduce(binding_identity_spelling(binding));
          row = %(capture $captured $captured_type $expression);
          facts[key] = row;
          facts[%(automatic $captured)] = 1;
          facts[%(type $captured)] = captured_type;
          facts[%(lambda-depth $captured)] = depth;
          if (reference) facts[%(reference-param $captured)] = 1;
          else facts[%(lambda-snapshot $captured)] = 1;
          List order = NULL;
          if (facts.try_get(%(lambda-order $scope), &stored)) order = stored;
          facts[%(lambda-order $scope)] = cons(row, order);
        }
        match (row)
          case %(capture ?captured ?captured_type ?): {
            binding = captured;
            type = captured_type;
          }
      }
  return %(expr $type (ident $binding));
}

/** Binds a constructed lambda through the lexical capture operations used by
    source literals. Parameter declarations keep their existing declarators;
    supplied canonical capture rows retain their value or reference mode.
*/
List Compiler.bind_lambda_expression(
  Compiler c, Type type, List parameters, List supplied, List body) {
  Array prescribed = %[], aliases = %[];
  foreach (List row, supplied)
    match (row)
      case %(capture ?target ?captured_type ?expression): {
        Type source = NULL, target_type = captured_type;
        List binding = target is <string>
                     ? c.sym.lookup(%($target), &source) : target.list();
        if (target_type.contains(<macro-expr>))
          target_type = source.car() == <&> ? source : cons(<&>, source);
        if (!binding_identity_spelling(binding)) {
          String spelling = target is <string> ? target.str() : NULL;
          match (binding) {
            case %((!is ?name type string)): spelling = name;
            case %("x2c.ident" (!is ?name type string)): spelling = name;
          }
          binding = c.sym.introduce(spelling);
          aliases.push(%($binding $target_type));
        }
        prescribed.push(%(capture $binding $target_type $expression));
      }
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  foreach (List alias, aliases)
    match (alias) case %(?binding ?captured_type): {
      Type annotation = captured_type;
      c.sym.bind_identity(
        NULL, binding, annotation.declaration_ast(binding));
    }
  List previous = c.lambda_scopes;
  c.begin_lambda_captures(NULL, prescribed.list_free());
  defer c.lambda_scopes = previous;
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  Array entries = %[];
  foreach (List entry, parameters.cdr()) {
    List declaration = NULL;
    match (entry) {
      case %(param ?base ?binding):
        declaration = c.bind_syntax(
          %(declare $base (bindings $binding)), AST_BLOCK, %("Var"));
      case %(binding ? ?):
        declaration = c.bind_syntax(
          %(declare ("Var") (bindings (bind $entry ()))),
          AST_BLOCK, %("Var"));
    }
    match (declaration)
      case %(declare ?base (bindings (!set ?declarator (bind ?binding ?)))): {
        c.semantic_binding_facts()[%(lambda-param $binding)] = 1;
        if (declaration.type_from_ast().car() == <&>)
          c.semantic_binding_facts()[%(reference-param $binding)] = 1;
        entries.push(%(param $base $declarator));
      }
  }
  match (body) {
    case %(block *): body = c.bind_syntax(body, AST_STATEMENT, %("Var"));
    default: body = c.resolve_expression(body, c.token);
  }
  List captures = c.end_lambda_captures();
  c.check_lambda_captures(body);
  parameters = %(params @{entries.list_free()});
  if (captures)
    return %(expr ("Func")
             (lambda $parameters (captures @captures) $body));
  if (type === %("Func")) {
    Type signature = %(
      (func ${_lambda_param_types_for_signature(c, parameters.cdr())}) "Var");
    return c.lift_func_expression(
      %(expr $signature (lambda $parameters $body)));
  }
  return %(expr $type (lambda $parameters $body));
}

/** Parses a `%!(...) => ...` literal and returns its typed lambda expression.
    Parameter bindings are in a new `Sym` scope, block bodies use `Var` as the
    active return type, and capture rows come from `semantic_binding_facts`.
    Capturing lambdas have type `Func`; noncapturing lambdas retain a native
    function type.
*/
List Compiler.parse_lambda_literal(Compiler c) {
  c.expect(<"%!">);
  c.expect(<(>);
  c.sym.push_new_scope();
  List names = %(), typed_params = NULL, int used_typed = 0;
  if (c.peek(0) != <)>) {
    if (_lambda_looks_typed(c)) {
      used_typed = 1;
      typed_params = _lambda_parse_typed_params(c, &names);
    }
    else names = _lambda_parse_bare_params(c);
  }
  c.expect(<)>);
  SymScope params = c.sym.pop_scope();
  Array references = %[], prescribed = %[];
  if (c.peek(0) == <ident> && c.token.text == %"using") {
    c.next();
    do {
      c.expect(<&>);
      if (c.macro_holes) {
        List name = NULL, value = NULL;
        Type reference = %(& <macro-expr>);
        if (c.peek(0) == <$>) {
          name = c.try_parse_macro_slot(<name>);
          value = %(expr (<macro-expr>) (ident $name));
        }
        else {
          Token origin = c.token;
          name = c.parse_basic_identifier();
          value = c.resolve_expression(%(expr () (ident $name)), origin);
          name = c.sym.lookup(name, NULL);
          reference = cons(<&>, value.cadr());
        }
        prescribed.push(%(
          capture $name $reference (expr $reference (op & $value))
        ));
        continue;
      }
      Token origin = c.token;
      String spelling = c.token.text;
      c.expect(<ident>);
      Type type = NULL;
      List binding = c.sym.lookup(%($spelling), &type);
      if (!type)
        c.report_error(
          <type>, %"identifier '$spelling' has no semantic type", origin, NULL);
      references.push(binding);
    } while (c.test(<,>));
  }
  _lambda_expect_arrow(c);
  List previous = c.lambda_scopes;
  c.begin_lambda_captures(references.list_free(), NULL);
  defer c.lambda_scopes = previous;
  c.sym.push_scope(params);

  List body = NULL;
  if (c.test(<"{">)) {
    Type previous_return = c.return_type;
    c.return_type = %("Var");
    {
      defer c.return_type = previous_return;
      body = c.parse_compound_statement();
    }
  }
  else body = c.parse_expression();
  List rtype = %("Var");
  List params_node = _lambda_params_node(names, typed_params, used_typed);
  List param_types = _lambda_param_types_for_signature(
    c, params_node.cdr());
  List ftype = %((func $param_types) @rtype);
  List captures = c.end_lambda_captures();
  c.check_lambda_captures(body);
  if (c.macro_holes) captures = prescribed.list_free();
  c.sym.pop_scope();
  if (captures)
    return %(expr ("Func")
             (lambda $params_node (captures @captures) $body));
  return %(expr $ftype (lambda $params_node $body));
}

static void _validate_match_binder_atom(Compiler compiler, Atom atom) {
  if (!compiler.in_pattern || !atom.is_atom()) return;
  char first = Atom.first(atom);
  if ((first != '?' && first != '*') || atom.is_binder()) return;
  int reserved = atom == <?binder?> || atom == <*binder?>;
  if (reserved && compiler.match_is && compiler.peek(1) == <)>) return;
  compiler.report_error(
    <parse>, "invalid match binder name",
    compiler.token, %( "binder-name:" ${atom.str()} ));
}

/** Parses the current atomic token into a typed expression and advances once.
    Pattern and macro-hole state control binder validation and quoting, while
    shallow parsing permits provisional numeric types.
*/
List Compiler.parse_atomic_literal(Compiler c) {
  String text = c.token.text, List literal = NULL;
  switch (c.peek(0)) {
    case <void>:       literal = %(literal ("Var") "void");   break;
    case <lit-char>:   literal = %(literal (char) $text);      break;
    case <lit-int>:
    case <lit-float>: {
      int floating = c.peek(0) == <lit-float>;
      Type type = Type.numeric_literal(text, floating);
      if (!type && c.shallow) type = floating ? %(double) : %(int);
      if (!type) c.report_error(
        <type>, "numeric literal is outside the supported scalar range",
        c.token, %( "literal:" $text ));
      literal = %(literal $type $text);
      break;
    }
    case <lit-char*>:  literal = %(literal (* char) $text);    break;
    case <lit-atom>: {
      String spelling = text.unescape(), Atom atom = Atom.intern(spelling);
      _validate_match_binder_atom(c, atom);
      if (atom is <symbol>)
        literal = %(literal ("Symbol") $text ${atom.symbol()});
      else {
        Var value = c.macro_holes && atom.is_binder()
                  ? %(!quote $atom).var() : atom;
        literal = %(literal ("Atom") $spelling $value);
      }
      break;
    }
    case <lit-symbol>: {
      String spelling = _symbol_source_spelling(text, 1);
      Symbol symbol = _exact_symbol_literal(c, c.token, spelling);
      _validate_match_binder_atom(c, symbol);
      literal = %(literal ("Symbol") $text $symbol);
      break;
    }
  }
  if (literal) {
    c.next();
    return %(expr ${literal.cadr()} $literal);
  }
  Symbol kind = c.peek(0);
  c.report_error(
    <parse>, "expected atomic expression",
    c.token,
    %( "token:" ${c.token.text} "kind:" ${kind.str()} ));
}
