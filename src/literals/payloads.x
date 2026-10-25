/*  payloads.x -- raise payloads and catch patterns */

static macro Stmt $fail.literals_symbol_bare(
  Expr $c, Expr $origin, Expr $owner, Expr $detail) {
  {
    String label = $owner == <raise> ? "raise" : "catch filter";
    String role = $detail ? "detail key" : "code";
    String hint = $owner == <raise>
      ? "use raise %(code (key value)...);"
      : "use catch %(code (key pattern)...):";
    $c.report_error(
      <parse>, %"$label $role must be a bare Symbol", $origin, %($hint));
  }
}

static macro Stmt $fail.literals_catch_detail(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "catch filter detail must be '*' or '(key pattern)'",
    $origin, %("wrap keyed detail patterns in parentheses"));

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
  with (c.runtime_literals = 1) {
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
  return _parse_bare_symbol(c, <raise>, 0);
}

static void _parse_raise_detail(Compiler c, Array args) {
  Token origin = c.token;
  c.expect(<(>);
  List key = c.try_parse_macro_slot(<expression>);
  if (!key)
    key = _parse_bare_symbol(c, <raise>, 1);
  List value = _parse_detail_value(
    c, origin, "raise detail requires exactly one value",
    "raise detail value cannot splice", %("pass one value expression"));
  args.push(key);
  args.push(value);
}

static List _parse_bare_symbol(
  Compiler c, Symbol owner, int detail) {
  Token token = c.token;
  if (c.peek(0) != <lit-atom>)
    $fail.literals_symbol_bare(c, token, owner, detail);
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
  with (c.in_pattern = 1, c.runtime_literals = 1) {
    List code = _parse_catch_code(c);
    Array elements = [];
    elements.push(code);
    while (c.peek(0) != <)>) _parse_catch_detail(c, elements);
    c.expect(<)>);
    List pattern = c.list_expression(elements, %(nil));
    elements.free();
    return pattern;
  }
}

static List _parse_catch_code(Compiler c) {
  if (c.peek(0) != <lit-atom>) return _parse_list_head(c);
  return _parse_bare_symbol(c, <catch>, 0);
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
    $fail.literals_catch_detail(c, origin);
  List key = _parse_bare_symbol(c, <catch>, 1);
  List value = _parse_detail_value(
    c, origin, "catch filter detail requires exactly one pattern",
    "catch filter detail pattern cannot splice",
    %("write one match pattern"));
  Array pair = [key, value];
  elements.push(c.list_expression(pair, %(nil)));
  pair.free();
}
