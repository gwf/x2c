/*  test-tokenizer.x -- semantic token-stream contract tests */

#include "test-support.x"
$(import "test-macros.xmacro")
#include <stdint.h>

static Tokenizer _lisp_tokens(char *source) {
  Tokenizer tokenizer = Tokenizer.new_mode(source, <lisp>);
  tokenizer.scan();
  return tokenizer;
}


static void tokenizer_next_starts_at_semantic_token(void) {
  Tokenizer tokenizer = _lisp_tokens(
    " \t// line\n/* block */#define X 1\nalpha");
  Token token = tokenizer.next();
  EXPECT_INT_EQ(token.type, <preproc>);
  EXPECT_STR_EQ(token.text, "#define X 1");
  token = tokenizer.next();
  EXPECT_INT_EQ(token.type, <ident>);
  EXPECT_STR_EQ(token.text, "alpha");
  EXPECT_INT_EQ(tokenizer.status(), <ok>);
}


static void tokenizer_next_repeats_eof(void) {
  Tokenizer tokenizer = _lisp_tokens("value");
  EXPECT_INT_EQ(tokenizer.next().type, <ident>);
  Token first = tokenizer.next(), second = tokenizer.next();
  EXPECT_INT_EQ(first.type, <eof>);
  EXPECT_TRUE(first == second);
}


static void tokenizer_status_owns_lexical_failures(void) {
  Tokenizer incomplete = _lisp_tokens("\"open");
  EXPECT_INT_EQ(incomplete.status(), <incomplete>);
  EXPECT_INT_EQ(incomplete.next().type, <error>);
  Token eof = incomplete.next();
  EXPECT_INT_EQ(eof.type, <eof>);
  EXPECT_TRUE(incomplete.next() == eof);

  Tokenizer symbol_escape = _lisp_tokens("<\"\\x");
  EXPECT_INT_EQ(symbol_escape.status(), <incomplete>);
  EXPECT_INT_EQ(symbol_escape.next().type, <error>);
  EXPECT_INT_EQ(symbol_escape.next().type, <eof>);

  Tokenizer malformed = _lisp_tokens("\"\\z\"");
  EXPECT_INT_EQ(malformed.status(), <malformed>);
  EXPECT_INT_EQ(malformed.next().type, <error>);
  EXPECT_INT_EQ(malformed.next().type, <eof>);
}


static void tokenizer_stray_close_keeps_lisp_mode(void) {
  Tokenizer tokenizer = _lisp_tokens(") tail");
  EXPECT_INT_EQ(tokenizer.status(), <ok>);
  EXPECT_INT_EQ(tokenizer.next().type, <")">);
  Token trailing = tokenizer.next();
  EXPECT_INT_EQ(trailing.type, <ident>);
  EXPECT_STR_EQ(trailing.text, "tail");
  EXPECT_INT_EQ(tokenizer.next().type, <eof>);
}

static void tokenizer_postfix_update_ends_operand(void) {
  Tokenizer tokenizer = Tokenizer.new("x++ < y; x-- > z;");
  tokenizer.scan();
  Symbol expected[] = {
    <ident>, <++>, <"<">, <ident>, <;>,
    <ident>, <-->, <">">, <ident>, <;>, <eof>
  };
  for (int i = 0; i < 11; i++)
    EXPECT_INT_EQ(tokenizer.next().type, expected[i]);
}


static void tokenizer_parenthesized_forms_stay_in_literal_modes(void) {
  Tokenizer tokenizer = Tokenizer.new(
    "%(a $(call(1)) @(tail()) c); %\"x$(call())y\""
  );
  tokenizer.scan();
  Symbol expected[] = {
    <"%(">, <lit-atom>, <$>, <(>, <lit-atom>, <(>, <lit-int>, <)>,
    <)>, <@>, <(>, <lit-atom>, <(>, <)>, <)>, <lit-atom>, <)>, <;>,
    <"%\"">, <segment>, <$>, <segment>, <"\"">, <eof>
  };
  for (int i = 0; i < 24; i++)
    EXPECT_INT_EQ(tokenizer.next().type, expected[i]);
  EXPECT_INT_EQ(tokenizer.status(), <ok>);
}


static void tokenizer_braced_literal_unquote_modes(void) {
  Tokenizer tokenizer = Tokenizer.new(
    "%(a ${call(1, %(b))} @{t()} \"x${call()}y\" c); %\"x${call()}y @{t}\""
  );
  tokenizer.scan();
  Symbol expected[] = {
    <"%(">, <lit-atom>, <"${">, <ident>, <(>, <lit-int>, <,>,
    <"%(">, <lit-atom>, <)>, <)>, <"}">,
    <"@{">, <ident>, <(>, <)>, <"}">,
    <"%\"">, <segment>, <"${">, <ident>, <(>, <)>, <"}">,
    <segment>, <"\"">, <lit-atom>, <)>, <;>,
    <"%\"">, <segment>, <"${">, <ident>, <(>, <)>, <"}">,
    <segment>, <"\"">, <eof>
  };
  for (int i = 0; i < 39; i++)
    EXPECT_INT_EQ(tokenizer.next().type, expected[i]);
  EXPECT_INT_EQ(tokenizer.status(), <ok>);
}


static void tokenizer_typed_capture_parentheses(void) {
  Tokenizer tokenizer = Tokenizer.new(
    "%(?($T value) ?(int (*)(String) fn) ? (String text) "
    "${call()} @{tail()}); int after;"
  );
  tokenizer.scan();
  Symbol expected[] = {
    <"%(">, <"?(">, <$>, <ident>, <ident>, <)>,
    <"?(">, <int>, <(>, <*>, <)>, <(>, <ident>, <)>, <ident>, <)>,
    <lit-atom>, <(>, <lit-atom>, <lit-atom>, <)>,
    <"${">, <ident>, <(>, <)>, <"}">,
    <"@{">, <ident>, <(>, <)>, <"}">, <)>, <;>, <int>, <ident>, <;>,
    <eof>
  };
  for (int i = 0; i < sizeof(expected) / sizeof(*expected); i++)
    EXPECT_INT_EQ(tokenizer.next().type, expected[i]);
  EXPECT_INT_EQ(tokenizer.status(), <ok>);
}


static void tokenizer_list_reader_prefixes(void) {
  Tokenizer tokenizer = Tokenizer.new("%(`(a ,(b) ,@tail))");
  tokenizer.scan();
  Symbol expected[] = {
    <"%(">, <"`">, <"(">, <lit-atom>, <",">, <"(">,
    <lit-atom>, <")">, <",@">, <lit-atom>, <")">, <")">, <eof>
  };
  for (int i = 0; i < 13; i++) {
    Token token = tokenizer.next();
    EXPECT_INT_EQ(token.type, expected[i]);
    if (i == 1) EXPECT_STR_EQ(token.text, "`");
    if (i == 4) EXPECT_STR_EQ(token.text, ",");
    if (i == 8) EXPECT_STR_EQ(token.text, ",@");
  }
  EXPECT_INT_EQ(tokenizer.status(), <ok>);
}


static void tokenizer_symbol_set_quotes_hold_the_terminator(void) {
  Tokenizer tokenizer = Tokenizer.new("%<<\"|=\" \">>\" plain>>");
  tokenizer.scan();
  Symbol expected[] = {
    <"%<<">, <lit-atom>, <lit-atom>, <lit-atom>, <">>">, <eof>
  };
  char *texts[] = { "%<<", "\"|=\"", "\">>\"", "plain", ">>" };
  for (int i = 0; i < 6; i++) {
    Token token = tokenizer.next();
    EXPECT_INT_EQ(token.type, expected[i]);
    if (i < 5) EXPECT_STR_EQ(token.text, texts[i]);
  }
  EXPECT_INT_EQ(tokenizer.status(), <ok>);

  // An unterminated entry fails the scan instead of truncating at `>>`.
  Tokenizer unterminated = Tokenizer.new("%<<\"open>>");
  unterminated.scan();
  EXPECT_INT_EQ(unterminated.status(), <malformed>);
  EXPECT_INT_EQ(unterminated.next().type, <"%<<">);
  EXPECT_INT_EQ(unterminated.next().type, <error>);
  EXPECT_INT_EQ(unterminated.next().type, <eof>);
}


static void tokenizer_failed_scan_preserves_source_and_mode(void) {
  $test.scoped();
  Tokenizer transfer_percent = Tokenizer.new("%(");
  Block percent_tokens = transfer_percent.tokens;
  size_t percent_width = percent_tokens.width;
  size_t percent_cap = percent_tokens.cap;
  percent_tokens.width = SIZE_MAX;
  percent_tokens.cap = percent_tokens.length;
  int caught = 0;
  try {
    transfer_percent.scan();
  }
  catch %(size-limit *rest): caught = 1;
  percent_tokens.width = percent_width;
  percent_tokens.cap = percent_cap;
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(transfer_percent.tokens.len(), 0);
  EXPECT_INT_EQ(transfer_percent.modes.len(), 1);
  EXPECT_TRUE(transfer_percent.modes[0] == <x2c>);
  EXPECT_INT_EQ(transfer_percent.pos, 0);

  Tokenizer transfer_operator = Tokenizer.new_mode("[", <list>);
  Block operator_tokens = transfer_operator.tokens;
  size_t operator_width = operator_tokens.width;
  size_t operator_cap = operator_tokens.cap;
  operator_tokens.width = SIZE_MAX;
  operator_tokens.cap = operator_tokens.length;
  caught = 0;
  try {
    transfer_operator.scan();
  }
  catch %(size-limit *rest): caught = 1;
  operator_tokens.width = operator_width;
  operator_tokens.cap = operator_cap;
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(transfer_operator.tokens.len(), 0);
  EXPECT_INT_EQ(transfer_operator.modes.len(), 1);
  EXPECT_TRUE(transfer_operator.modes[0] == <list>);
  EXPECT_INT_EQ(transfer_operator.pos, 0);

}



void tokenizer_suite(void) {
  $test.run(tokenizer_next_starts_at_semantic_token);
  $test.run(tokenizer_next_repeats_eof);
  $test.run(tokenizer_status_owns_lexical_failures);
  $test.run(tokenizer_stray_close_keeps_lisp_mode);
  $test.run(tokenizer_postfix_update_ends_operand);
  $test.run(tokenizer_parenthesized_forms_stay_in_literal_modes);
  $test.run(tokenizer_braced_literal_unquote_modes);
  $test.run(tokenizer_typed_capture_parentheses);
  $test.run(tokenizer_list_reader_prefixes);
  $test.run(tokenizer_symbol_set_quotes_hold_the_terminator);
  $test.run(tokenizer_failed_scan_preserves_source_and_mode);
}
