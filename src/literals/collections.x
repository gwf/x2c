/*  collections.x -- Array, Map and SymbolSet literals */

static macro Stmt $fail.literals_symbol_duplicate(
  Expr $c, Expr $origin, Expr $symbol) =>
  $c.report_error(
    <parse>, "duplicate Symbol in symbol set",
    $origin, $("symbol:", $symbol.repr()));

static macro Stmt $fail.literals_symbol_literal(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "symbol-set entries must be literal Symbols",
    $origin, %("use %<foo bar>"));

/* Symbol sets

   `%<...>` builds an immutable SymbolSet, one C string that holds a
   header, a hash table, and the Symbols in source order. `SymbolSet.encode`
   in `lib/symbolset.x` builds it. */

/** Parses a `%<...>` literal into an immutable ordered `SymbolSet`.
    Entries must be literal compact `Symbol`s; source order defines dense
    indexes and an equal encoded `Symbol` reports a duplicate diagnostic.
*/
List Compiler.parse_symbol_set_literal(Compiler c) {
  c.expect(<"%<">);
  Array symbols = [], tokens = [];
  while (c.peek(0) != <">">) {
    symbols.push(_member_symbol(c));
    tokens.push(c.token);
    c.next();
  }
  c.expect(<">">);
  int duplicate = -1;
  List set = c.symbol_set_expression(symbols, duplicate);
  if (duplicate >= 0) {
    Token token = tokens[duplicate];
    Symbol symbol = symbols[duplicate];
    $fail.literals_symbol_duplicate(c, token, symbol);
  }
  symbols.free();
  tokens.free();
  return set;
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

/* Arrays and Maps

   `%[...]` and `%{...}` read quoted elements. A Map entry, quoted or
   evaluated, may come from an entry-position macro, whose `(seq ...)` rows
   join the entries in source order. */

/** Parses a quoted Array literal into a typed, source-ordered `(array ...)`
    node and consumes its closing `]`.
*/
List Compiler.parse_array_literal(Compiler c) {
  c.expect(<"%[">);
  List elems = _parse_array_elements(c);
  c.expect(<"]">);
  return %(expr ("Array") (array @elems));
}

/** Parses a quoted Map literal into a typed, source-ordered `(map ...)` node
    and consumes its closing `}`.
*/
List Compiler.parse_map_literal(Compiler c) {
  c.expect(<"%{">);
  Array entries = [];
  while (c.peek(0) != <"}">) {
    _push_entry(entries, _parse_quoted_entry(c));
    if (c.peek(0) == <"}">) break;
    c.expect(<,>);
  }
  List elems = entries.list_free();
  c.expect(<"}">);
  return %(expr ("Map") (map @elems));
}

/** Parses comma-separated `Map` entries up to but not including `}`.
    `Entry`-position macro sequences are flattened in source order.
*/
List Compiler.parse_map_entries(Compiler c) => _parse_map_entries(c, 0);

/** Parses an evaluated Map, `${key: value, ...}`, whose bare identifier
    keys are expressions like any other key, and consumes its `}`. In code
    `$` and `{` are two tokens; quoted data scans `${` as one.
*/
List Compiler.parse_evaluated_map(Compiler c) {
  if (!c.test(<"${">)) {
    c.expect(<$>);
    c.expect(<"{">);
  }
  List entries = _parse_map_entries(c, 1);
  c.expect(<"}">);
  return %(expr ("Map") (map @entries));
}

/** Parses one `Map` entry without consuming its following comma or `}`.
    A bare identifier key is an Atom; any other key is an expression.
    A direct row returns a resolved `(map-entry KEY VALUE)` node; an
    entry-position macro may return `(seq ...)` for its caller to splice.
*/
List Compiler.parse_map_entry(Compiler c) => _parse_map_entry(c, 0);

// collection and SymbolSet literals

static Symbol _member_symbol(Compiler c) {
  Token token = c.token;
  Symbol kind = c.peek(0);
  if (kind != <lit-atom> && kind != <lit-symbol>)
    $fail.literals_symbol_literal(c, token);
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

static int _duplicate_index(List values) {
  Map seen = {};
  int index = 0;
  foreach (Symbol value in values) {
    if (value in seen) return index;
    seen[value] = 1;
    index++;
  }
  return -1;
}

static List _set_expression(Array symbols) {
  auto {
    String text = _octal_literal(SymbolSet.encode(symbols));
    List bytes = %(expr (* char) (literal (* char) $text));
    List decl = %(decl ("SymbolSet") (bindings (bind () ())));
    return %(expr ("SymbolSet") (cast $decl $bytes));
  }
}

/* Three-digit escapes preserve each byte inside one quoted C string. */
static String _octal_literal(Block bytes) {
  unsigned char *data = bytes.bytes;
  Buffer output = Buffer.new(0);
  output.write("\"");
  for (size_t at = 0; at < bytes.len(); at++)
    output.printf("\\%03o", (unsigned) data[at]);
  output.write("\"");
  return output.str_free();
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

/* An Expr sequence hole fills one quoted Array argument position. */
static List _parse_array_element(Compiler c) {
  List slot = c.try_parse_macro_slot(<argument>);
  if (slot) return slot;
  if (c.peek(0) == <"$("> && c.peek(1) == <@>) {
    c.next();
    slot = c.try_parse_macro_slot(<argument>);
    c.expect(<)>);
    return slot;
  }
  return _parse_element(c);
}

/* An Array or Map element has no splice form. */
static List _parse_element(Compiler c) {
  List inserted = _parse_insertion(c);
  return inserted ? inserted : _parse_literal_element(c);
}

static void _push_entry(Array entries, Ast entry) {
  if (entry && entry.car() == <seq>)
    foreach (List row in entry.cdr()) entries.push(row);
  else if (entry) entries.push(entry);
}

/* `$(...)` holds a macro-produced entry or an expression key. */
static List _parse_quoted_entry(Compiler c) {
  Token origin = c.token;
  List slot = c.try_parse_macro_slot(<map-entry>);
  if (slot) return slot;
  if (!c.test(<"$(">)) return _entry_value(c, _parse_element(c), origin);
  List entry = c.try_parse_macro_slot(<map-entry>);
  if (!entry) entry = c.try_parse_macro_target_at(<map-entry>);
  if (entry) {
    c.expect(<)>);
    return entry;
  }
  List key = c.parse_expression();
  c.expect(<)>);
  return _entry_value(c, key, origin);
}

static List _entry_value(Compiler c, List key, Token origin) {
  c.expect(<:>);
  List value = _parse_element(c);
  return c.resolve_map_entry(%(map-entry $key $value), origin);
}

static List _parse_map_entries(Compiler c, int evaluated) {
  Array entries = [];
  while (c.peek(0) != <"}">) {
    _push_entry(entries, _parse_map_entry(c, evaluated));
    if (c.peek(0) == <"}">) break;
    c.expect(<,>);
  }
  return entries.list_free();
}

static List _parse_map_entry(Compiler c, int evaluated) {
  List slot = c.try_parse_macro_slot(<map-entry>);
  if (slot) return slot;
  List macro = c.try_parse_macro_target_at(<map-entry>);
  if (macro) return macro;
  Token origin = c.token;
  List key = NULL;
  if (!evaluated && c.peek(0) == <ident> && c.peek(1) == <:>) {
    List literal = _atom_literal(c, c.token.text);
    c.next();
    key = %(expr $(literal.cadr()) $literal);
  }
  else key = c.parse_assignment();
  c.expect(<:>);
  List value = c.parse_assignment();
  return c.resolve_map_entry(%(map-entry $key $value), origin);
}
