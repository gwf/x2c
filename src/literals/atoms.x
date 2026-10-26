/*  atoms.x -- scalar literals and Symbol decoding */

static macro Stmt $fail.literals_atom_expected(
  Expr $c, Expr $site, Expr $kind) =>
  $c.report_error(
    <parse>, "expected atomic expression",
    $site, $("token:", $c.token.text, "kind:", $kind.str()));

static macro Stmt $fail.literals_number_range(
  Expr $c, Expr $site, Expr $text) =>
  $c.report_error(
    <type>, "numeric literal is outside the supported scalar range",
    $site, $("literal:", $text));

static macro Stmt $fail.literals_binder_name(
  Expr $c, Expr $site, Expr $atom) =>
  $c.report_error(
    <parse>, "invalid match binder name",
    $site, $("binder-name:", $atom.str()));

static macro Stmt $fail.literals_symbol_truncated(
  Expr $c, Expr $origin, Expr $spelling, Expr $lossy) =>
  $c.report_error(
    <parse>, "Symbol literal does not round-trip",
    $origin, %("source spelling: $($spelling)"
      "encoded spelling: $($lossy)"));

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
    return %(expr $(literal.cadr()) $literal);
  }
  Symbol kind = c.peek(0);
  $fail.literals_atom_expected(c, c.token, kind);
}

/* Shallow declaration discovery gives a number outside every supported
   scalar type a provisional type. */
static List _number_literal(Compiler c, String text, int floating) {
  Type type = Type.numeric_literal(text, floating);
  if (!type && c.shallow) type = floating ? %(double) : %(int);
  if (!type)
    $fail.literals_number_range(c, c.token, text);
  return %(literal $type $text);
}

/* A bare spelling names an Atom, which is a compact Symbol when it fits. */
module List _atom_literal(Compiler c, String text) {
  String spelling = text.unescape(), Atom atom = Atom.intern(spelling);
  _check_binder(c, atom);
  if (spelling in c.object_macros) _warn_macro_name(c, spelling);
  if (atom is <symbol>) return %(literal ("Symbol") $text $(atom.symbol()));
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
  $fail.literals_binder_name(c, c.token, atom);
}

/* The preprocessor never sees a literal, so a macro's name here is data.
   The author who wanted its value must unquote it. */
static void _warn_macro_name(Compiler c, String spelling) {
  String unquoted = "$((long) " + spelling + ")";
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
module String _angle_spelling(String text) {
  int len = text.len();
  if (len >= 4 && text[1] == '"')
    return String.new_len(text + 2, len - 4).unescape();
  return String.new_len(text + 1, len - 2);
}

/* A compact Symbol literal must decode to its source spelling. */
module Symbol _exact_symbol(
  Compiler c, Token token, String spelling) {
  Symbol symbol;
  if (Symbol.try_new(spelling, &symbol)) return symbol;
  Symbol lossy = spelling ? Symbol.new(spelling) : 0;
  $fail.literals_symbol_truncated(c, token, spelling, lossy);
}
