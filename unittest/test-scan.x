/*  test-scan.x -- character scanner contract tests */

#include "test-support.x"
#include <string.h>

static void scan_whitespace_and_positions(void) {
  EXPECT_INT_EQ(scan_white_space(" \t\r\n\v\frest"), 6);
  EXPECT_INT_EQ(scan_white_space("rest"), 0);
  EXPECT_INT_EQ(scan_white_space(""), -1);

  int line = 3, col = 5;
  scan_next_line_col("ab\ncd\nx", 7, &line, &col);
  EXPECT_INT_EQ(line, 5);
  EXPECT_INT_EQ(col, 2);

  line = 2; col = 4;
  scan_next_line_col("plain", 5, &line, &col);
  EXPECT_INT_EQ(line, 2);
  EXPECT_INT_EQ(col, 9);
}

static void scan_prefix_failures_transfer(void) {
  int caught = 0;
  try scan_line_comment(NULL);
  catch %(bad-arg *): caught++;
  try scan_line_comment("/* no");
  catch %(bad-arg *): caught++;

  Symbol status = <unchanged>;
  try scan_block_comment_status("// no", &status);
  catch %(bad-arg *): caught++;
  EXPECT_TRUE(status == <unchanged>);
  try scan_identifier("1bad");
  catch %(bad-arg *): caught++;
  try scan_identifier(NULL);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 5);
}


static void scan_comments_and_preprocessor(void) {
  char line_eof[] = "// comment";
  char line_newline[] = "// comment\nnext";
  EXPECT_INT_EQ(scan_line_comment(line_eof), strlen(line_eof));
  EXPECT_INT_EQ(scan_line_comment(line_newline), 10);
  EXPECT_INT_EQ(scan_line_comment("//\n"), 2);

  EXPECT_INT_EQ(scan_block_comment("/* simple */"), 12);
  EXPECT_INT_EQ(scan_block_comment("/* multi\nline */"), 16);
  EXPECT_INT_EQ(scan_block_comment("/* unclosed"), -1);

  char directive[] = "#define X 1";
  EXPECT_INT_EQ(scan_preprocessor(directive), strlen(directive));
  EXPECT_INT_EQ(scan_preprocessor("#x\nnext"), 2);
  EXPECT_INT_EQ(scan_preprocessor("#x\\\ny\n"), 5);
  EXPECT_INT_EQ(scan_preprocessor("#x\\\r\ny\n"), 6);
  EXPECT_INT_EQ(scan_preprocessor("#x\\"), -1);
}


struct KeywordCase {
  char *text;
  Symbol type;
};


static void scan_identifiers_and_keywords(void) {
  EXPECT_INT_EQ(scan_identifier("alpha_123+"), 9);
  EXPECT_INT_EQ(scan_identifier("_private "), 8);

  struct KeywordCase cases[] = {
    {"associated", <associated>},
    {"auto", <auto>}, {"break", <break>}, {"case", <case>},
    {"catch", <catch>}, {"char", <char>}, {"const", <const>},
    {"continue", <continue>}, {"default", <default>},
    {"defer", <defer>}, {"do", <do>}, {"double", <double>},
    {"else", <else>}, {"enum", <enum>}, {"extern", <extern>},
    {"float", <float>}, {"finally", <finally>}, {"for", <for>},
    {"goto", <goto>}, {"if", <if>}, {"in", <in>},
    {"inline", <inline>}, {"match", <match>}, {"int", <int>},
    {"long", <long>}, {"protocol", <protocol>},
    {"register", <register>},
    {"raise", <raise>}, {"restrict", <restrict>}, {"return", <return>},
    {"short", <short>}, {"signed", <signed>},
    {"sizeof", <sizeof>}, {"static", <static>},
    {"struct", <struct>}, {"switch", <switch>},
    {"try", <try>}, {"typedef", <typedef>},
    {"union", <union>}, {"unsigned", <unsigned>}, {"void", <void>},
    {"volatile", <volatile>}, {"while", <while>}
  };
  int count = sizeof(cases) / sizeof(cases[0]);
  for (int i = 0; i < count; i++) {
    int len = strlen(cases[i].text);
    EXPECT_TRUE(scan_keyword_type(cases[i].text, len) == cases[i].type);
    EXPECT_INT_EQ(scan_keyword(cases[i].text), len);
  }
  EXPECT_INT_EQ(scan_keyword("identifier"), -1);
  EXPECT_INT_EQ(scan_keyword("throw"), -1);
  EXPECT_INT_EQ(scan_keyword("WHILE"), -1);
  EXPECT_INT_EQ(scan_keyword_type("continue_more", 13), 0);

  Scope.retain();
  EXPECT_INT_EQ(scan_keyword("while"), 5);
  Scope.release();
  EXPECT_INT_EQ(scan_keyword("while"), 5);
}


static void scan_operators(void) {
  EXPECT_INT_EQ(scan_c_operator("..."), 3);
  EXPECT_INT_EQ(scan_c_operator(">>="), 3);
  EXPECT_INT_EQ(scan_c_operator("!=="), 3);
  EXPECT_INT_EQ(scan_c_operator("++"), 2);
  EXPECT_INT_EQ(scan_c_operator("->"), 2);
  EXPECT_INT_EQ(scan_c_operator("@"), 1);
  EXPECT_INT_EQ(scan_c_operator("#"), -1);
}


static void scan_byte_escapes_and_segments(void) {
  EXPECT_INT_EQ(scan_escape_sequence("\\n"), 2);
  EXPECT_INT_EQ(scan_escape_sequence("\\101"), 4);
  EXPECT_INT_EQ(scan_escape_sequence("\\x"), -1);
  EXPECT_INT_EQ(scan_escape_sequence("\\x0"), 3);
  EXPECT_INT_EQ(scan_escape_sequence("\\x123"), 4);
  EXPECT_INT_EQ(scan_escape_sequence("\\u12"), 4);
  EXPECT_INT_EQ(scan_escape_sequence("\\z"), -1);
  EXPECT_INT_EQ(scan_escape_sequence("\\\r\n"), 3);

  EXPECT_INT_EQ(scan_string_segment("plain$"), 5);
  EXPECT_INT_EQ(scan_string_segment("left$$right\""), 11);
  EXPECT_INT_EQ(scan_string_segment("\\$value$"), 7);
  EXPECT_INT_EQ(scan_string_segment("line1\nline2\""), 11);
  EXPECT_INT_EQ(scan_string_segment("\\u12$"), 4);
  EXPECT_INT_EQ(scan_string_segment("unterminated"), -1);
}


static void scan_c_literals(void) {
  EXPECT_INT_EQ(scan_c_string("\"hello\""), 7);
  EXPECT_INT_EQ(scan_c_string("\"\\x123\""), 7);
  EXPECT_INT_EQ(scan_c_string("\"\\u0041\""), 8);
  EXPECT_INT_EQ(scan_c_string("\"\\U00000041\""), 12);
  EXPECT_INT_EQ(scan_c_string("\"\\u12\""), -1);
  EXPECT_INT_EQ(scan_c_string("\"\\z\""), -1);

  char raw_string[] = {'"', 'a', '\n', 'b', '"', 0};
  char raw_char[] = {'\'', '\n', '\'', 0};
  EXPECT_INT_EQ(scan_c_string(raw_string), -1);
  EXPECT_INT_EQ(scan_c_character(raw_char), -1);

  EXPECT_INT_EQ(scan_c_character("'a'"), 3);
  EXPECT_INT_EQ(scan_c_character("'\\101'"), 6);
  EXPECT_INT_EQ(scan_c_character("'\\u0041'"), 8);
  EXPECT_INT_EQ(scan_c_character("''"), -1);
  EXPECT_INT_EQ(scan_c_character("'ab'"), -1);
}


struct NumberCase {
  char *text;
  int len;
  Symbol type;
};


static void scan_valid_numbers(void) {
  struct NumberCase cases[] = {
    {"0", 1, <int>}, {"123", 3, <int>}, {"123UL;", 5, <int>},
    {"0123", 4, <int>}, {"08", 2, <int>}, {"0o777", 5, <int>},
    {"0b101", 5, <int>}, {"0x1e", 4, <int>},
    {"-0x1e", 5, <int>}, {".5", 2, <float>},
    {"1.", 2, <float>}, {"1.e2", 4, <float>},
    {"1.0e2", 5, <float>}, {"1e-2f;", 5, <float>},
    {"0x1p2", 5, <float>}, {"0x1.p1", 6, <float>},
    {"0x.2p1", 6, <float>}
  };
  int count = sizeof(cases) / sizeof(cases[0]);
  for (int i = 0; i < count; i++) {
    Symbol type = 0;
    EXPECT_INT_EQ(scan_number_typed(cases[i].text, &type), cases[i].len);
    EXPECT_TRUE(type == cases[i].type);
    EXPECT_INT_EQ(scan_number(cases[i].text), cases[i].len);
    EXPECT_TRUE(scan_number_type(cases[i].text, cases[i].len) ==
                cases[i].type);
  }

  EXPECT_INT_EQ(scan_digital("123.5"), 5);
  EXPECT_INT_EQ(scan_digital("1e2"), 3);
  EXPECT_INT_EQ(scan_digital(".5"), 2);
  EXPECT_INT_EQ(scan_float("25e2;"), 4);
  EXPECT_INT_EQ(scan_float("e2;"), 2);
  EXPECT_INT_EQ(scan_hexponent("+2f;"), 3);
  EXPECT_TRUE(scan_number_type("1.0tail", 3) == <float>);
  EXPECT_INT_EQ(scan_number("+42;"), 3);
}


static void scan_malformed_numbers(void) {
  char *cases[] = {
    "0x", "0b", "0o", "0x;", "0b2;", "0o8;", "018;",
    "1e;", "1e+;", "0x1p;", "0x1p+;", "0x1p+f;", "0x1.2;"
  };
  int count = sizeof(cases) / sizeof(cases[0]);
  for (int i = 0; i < count; i++) EXPECT_INT_EQ(scan_number(cases[i]), -1);
  EXPECT_INT_EQ(scan_hexponent("+;"), -1);
  EXPECT_INT_EQ(scan_digital("."), -1);
}


static void scan_symbols(void) {
  EXPECT_INT_EQ(scan_atom("alpha rest"), 5);
  EXPECT_INT_EQ(scan_atom("alpha\\ beta)"), 11);
  EXPECT_INT_EQ(scan_atom("\\"), -1);
  EXPECT_INT_EQ(scan_atom("alpha\\"), -1);
  EXPECT_INT_EQ(scan_atom("alpha,beta"), 5);
  EXPECT_INT_EQ(scan_atom("alpha\"beta"), 5);
  EXPECT_INT_EQ(scan_atom("alpha$rest"), 5);
  EXPECT_INT_EQ(scan_atom("`quoted"), 0);

  EXPECT_INT_EQ(scan_symbol_literal("not-angle"), 0);
  EXPECT_INT_EQ(scan_symbol_literal("<alpha>"), 7);
  EXPECT_INT_EQ(scan_symbol_literal("<\"a b\">"), 7);
  EXPECT_INT_EQ(scan_symbol_literal("<>"), -1);
  EXPECT_INT_EQ(scan_symbol_literal("<a b>"), -1);
  EXPECT_INT_EQ(scan_symbol_literal("<a\vb>"), -1);
  EXPECT_INT_EQ(scan_symbol_literal("<\"\\u12\">"), 8);
  EXPECT_INT_EQ(scan_symbol_literal("<unterminated"), -1);
}


static void scan_lisp_status_variants(void) {
  Symbol status = <malformed>;
  EXPECT_INT_EQ(scan_block_comment_status("/* done */", &status), 10);
  EXPECT_INT_EQ(status, <ok>);
  EXPECT_INT_EQ(scan_block_comment_status("/* open", &status), -1);
  EXPECT_INT_EQ(status, <incomplete>);

  EXPECT_INT_EQ(scan_c_string_status("\"done\"", &status), 6);
  EXPECT_INT_EQ(status, <ok>);
  EXPECT_INT_EQ(scan_c_string_status("\"open", &status), -1);
  EXPECT_INT_EQ(status, <incomplete>);
  EXPECT_INT_EQ(scan_c_string_status("\"tail\\", &status), -1);
  EXPECT_INT_EQ(status, <incomplete>);
  EXPECT_INT_EQ(scan_c_string_status("\"\\u12", &status), -1);
  EXPECT_INT_EQ(status, <incomplete>);
  EXPECT_INT_EQ(scan_c_string_status("\"\\u12\"", &status), -1);
  EXPECT_INT_EQ(status, <malformed>);
  EXPECT_INT_EQ(scan_c_string_status("\"\\z\"", &status), -1);
  EXPECT_INT_EQ(status, <malformed>);
  char raw[] = {'"', 'a', '\n', 'b', '"', 0};
  EXPECT_INT_EQ(scan_c_string_status(raw, &status), -1);
  EXPECT_INT_EQ(status, <malformed>);

  EXPECT_INT_EQ(scan_atom_status("name\\", &status), -1);
  EXPECT_INT_EQ(status, <incomplete>);
  EXPECT_INT_EQ(scan_symbol_literal_status("<open", &status), -1);
  EXPECT_INT_EQ(status, <incomplete>);
  EXPECT_INT_EQ(scan_symbol_literal_status("<\"open", &status), -1);
  EXPECT_INT_EQ(status, <incomplete>);
  EXPECT_INT_EQ(scan_symbol_literal_status("<\"\\x", &status), -1);
  EXPECT_INT_EQ(status, <incomplete>);
  EXPECT_INT_EQ(scan_symbol_literal_status("<\"\\u12", &status), -1);
  EXPECT_INT_EQ(status, <incomplete>);
  EXPECT_INT_EQ(scan_symbol_literal_status("<>", &status), -1);
  EXPECT_INT_EQ(status, <malformed>);
  EXPECT_INT_EQ(scan_symbol_literal_status("<a b>", &status), -1);
  EXPECT_INT_EQ(status, <malformed>);
  EXPECT_INT_EQ(scan_symbol_literal_status("<\"\\xG\">", &status), -1);
  EXPECT_INT_EQ(status, <malformed>);
  EXPECT_INT_EQ(scan_symbol_literal_status("<\"\\z\">", &status), -1);
  EXPECT_INT_EQ(status, <malformed>);
}


$(import "test-macros.xmacro")

void scan_suite(void) {
  $test.run(scan_prefix_failures_transfer);
  $test.run(scan_whitespace_and_positions);
  $test.run(scan_comments_and_preprocessor);
  $test.run(scan_identifiers_and_keywords);
  $test.run(scan_operators);
  $test.run(scan_byte_escapes_and_segments);
  $test.run(scan_c_literals);
  $test.run(scan_valid_numbers);
  $test.run(scan_malformed_numbers);
  $test.run(scan_symbols);
  $test.run(scan_lisp_status_variants);
}
