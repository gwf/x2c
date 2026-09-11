/*  test-symbol.x -- unit tests for symbol encoding */

#include "test-support.x"
$(import "test-macros.xmacro")
#include <string.h>

static void symbol_interning_and_var(void) {
  Symbol a = <alpha>, b = <alpha>;
  EXPECT_TRUE(a == b);

  Var va = a, vb = b;
  EXPECT_TRUE(va == vb);
  EXPECT_TRUE(va.symbol() == a);
}

static void symbol_length_boundaries(void) {
  Symbol five = <abcdefghij>;
  EXPECT_INT_EQ(five.len(), 10);
  EXPECT_TRUE(five.first() == 'a');
  EXPECT_TRUE(five.last() == 'j');

  Symbol seven = <"Token@!">;
  EXPECT_INT_EQ(seven.len(), 7);
  String copy = seven;
  EXPECT_TRUE(copy == %"Token@!");
}

static void symbol_invalid_inputs(void) {
  Symbol nullish = Symbol.new_len(NULL, 0);
  EXPECT_INT_EQ(nullish, 0);
  Symbol empty = Symbol.new_len("", 0);
  EXPECT_INT_EQ(empty, 0);
}

static void symbol_try_new_requires_exact_spelling(void) {
  Symbol symbol = <unchanged>;
  EXPECT_TRUE(Symbol.try_new(%"abcdefghij", &symbol));
  EXPECT_TRUE(symbol == <abcdefghij>);
  EXPECT_TRUE(Symbol.try_new(NULL, &symbol));
  EXPECT_INT_EQ(symbol, 0);

  symbol = <unchanged>;
  EXPECT_FALSE(Symbol.try_new(%"read_only", &symbol));
  EXPECT_TRUE(symbol == <unchanged>);
  EXPECT_FALSE(Symbol.try_new(%"abcdefghijk", &symbol));
  EXPECT_TRUE(symbol == <unchanged>);
  EXPECT_FALSE(Symbol.try_new(%"Token@!!", &symbol));
  EXPECT_TRUE(symbol == <unchanged>);
  EXPECT_FALSE(Symbol.try_new(%"exact", NULL));
}

static void symbol_truncates_5bit_preferred(void) {
  Symbol prefix = <abcdefghij>;
  Symbol longish = Symbol.new("abcdefghijklmno");
  EXPECT_TRUE(longish == prefix);
  String decoded = longish;
  EXPECT_TRUE(decoded == %"abcdefghij");
}

static void symbol_truncates_mixed_to_7bit(void) {
  Symbol mixed = Symbol.new("abc@defghi");
  Symbol truncated = Symbol.new("abc@defzzz");
  EXPECT_TRUE(mixed == truncated);
  EXPECT_INT_EQ(mixed.len(), 7);
  String decoded = mixed;
  EXPECT_TRUE(decoded == %"abc@def");
}

static void symbol_repr_variants(void) {
  Symbol simple = <alpha>;
  String repr_simple = simple.repr();
  EXPECT_STR_EQ(repr_simple, "<alpha>");

  Symbol complex = <"Token@!">;
  String repr_complex = complex.repr();
  EXPECT_STR_EQ(repr_complex, "<\\\"Token@!\\\">");

  Symbol escaped = Symbol.new("line\n");
  String repr_escaped = escaped.repr(), repr_expected = "<\\\"line\n\\\">";
  EXPECT_STR_EQ(repr_escaped, repr_expected);
}

static void symbol_repr_short_7bit_values(void) {
  Symbol one = Symbol.new("@"), two = Symbol.new("@#");
  EXPECT_STR_EQ(one.repr(), "<\\\"@\\\">");
  EXPECT_STR_EQ(two.repr(), "<\\\"@#\\\">");
}

static void symbol_repr_uses_encoding(void) {
  Symbol forced = ((((((Symbol) 'A' << 7) | 'B') << 7) | 'C') << 1) | 1;
  EXPECT_STR_EQ(forced.str(), "ABC");
  EXPECT_STR_EQ(forced.repr(), "<\\\"ABC\\\">");

  Buffer out = Buffer.new(0);
  forced.write_repr(out);
  EXPECT_STR_EQ(out.str_free(), forced.repr());

  Var boxed = forced;
  EXPECT_STR_EQ(boxed.repr(), forced.repr());
}

static void symbol_repr_escapes_match_writer(void) {
  Symbol quote = Symbol.new("\""), slash = Symbol.new("\\");
  Buffer out = Buffer.new(0);

  quote.write_repr(out);
  EXPECT_STR_EQ(out.str(), quote.repr());

  out.clear();
  slash.write_repr(out);
  EXPECT_STR_EQ(out.str_free(), slash.repr());
}

static void symbol_parse_modes(void) {
  char angled[] = "<alpha>";
  Symbol parsed = Symbol.parse(angled);
  EXPECT_TRUE(parsed == <alpha>);

  char quoted[] = "<\"Token@!\">";
  Symbol parsed_quoted = Symbol.parse(quoted);
  EXPECT_TRUE(parsed_quoted == <"Token@!">);

  char listy[] = "gamma rest";
  Symbol parsed_list = Symbol.parse(listy);
  EXPECT_TRUE(parsed_list == <gamma>);
}

static void symbol_parse_malformed_returns_zero(void) {
  char trailing_escape[] = "\\";
  EXPECT_INT_EQ(Symbol.parse(trailing_escape), 0);
}

static void symbol_parse_empty_quoted(void) {
  Symbol s = Symbol.parse(%"<\"\">"), empty = Symbol.new_len("", 0);
  EXPECT_INT_EQ((int)(s == empty), 1);
}

// A line-continuation escape scans as valid but unescapes to zero bytes.
static void symbol_parse_escape_collapses_to_empty(void) {
  Symbol s = Symbol.parse(%"<\"\\\n\">"), empty = Symbol.new_len("", 0);
  EXPECT_INT_EQ((int)(s == empty), 1);
}

static void symbol_compare_lexicographic(void) {
  Symbol alpha = <alpha>, beta = <beta>;
  EXPECT_TRUE(alpha.compare(beta) < 0);
  EXPECT_TRUE(beta.compare(alpha) > 0);
  EXPECT_INT_EQ(alpha.compare(alpha), 0);
  EXPECT_TRUE(Symbol.compare(0, alpha) < 0);
  EXPECT_TRUE(alpha.compare(0) > 0);
}

static void symbol_compare_constructible_values(void) {
  char ab[] = {'a', 0, 'b'}, ac[] = {'a', 0, 'c'};
  Symbol sab = Symbol.new_len(ab, 3), sac = Symbol.new_len(ac, 3);
  EXPECT_FALSE(sab == sac);
  EXPECT_TRUE(sab.compare(sac) < 0);
  EXPECT_TRUE(sac.compare(sab) > 0);
}


void symbol_suite(void) {
  $test.run(symbol_interning_and_var);
  $test.run(symbol_length_boundaries);
  $test.run(symbol_invalid_inputs);
  $test.run(symbol_try_new_requires_exact_spelling);
  $test.run(symbol_truncates_5bit_preferred);
  $test.run(symbol_truncates_mixed_to_7bit);
  $test.run(symbol_repr_variants);
  $test.run(symbol_repr_short_7bit_values);
  $test.run(symbol_repr_uses_encoding);
  $test.run(symbol_repr_escapes_match_writer);
  $test.run(symbol_parse_modes);
  $test.run(symbol_parse_malformed_returns_zero);
  $test.run(symbol_parse_empty_quoted);
  $test.run(symbol_parse_escape_collapses_to_empty);
  $test.run(symbol_compare_lexicographic);
  $test.run(symbol_compare_constructible_values);
}
