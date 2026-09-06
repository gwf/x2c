/*  test-interpolation.x -- unit tests for interpolation features */

#include "test-support.x"

// A user typedef of a numeric together with its converter.  Interpolating
// one takes the T_str lookup, which is the path a bare builtin cannot
// take: the collector records this parameter as the string "Celsius", so
// the lookup matches, where a builtin's int never does.  Symbol below is
// the same shape from the runtime, and both are here because a guard that
// judged segments by numeric-ness instead of by asking the lookup once
// silently turned them into empty strings.
typedef int Celsius;

String Celsius.str(Celsius c) {
  return %"C%d".printf((int) c);
}

// A file-scope alias of Var.  A segment declared with this name has to
// reach Var.str the way a canonical Var does, which is what proves the
// interpolation owner asks the semantic environment instead of comparing
// the annotation against the literal spelling "Var".
typedef Var Reading;

static void interp_list_value(void) {
  int x = 42;
  List lst = %( a $x b );
  EXPECT_LIST_EQ(lst, %( a 42 b ));
}

static void interp_list_expr(void) {
  int x = 41;
  List lst = %( a ${x + 1} b );
  EXPECT_LIST_EQ(lst, %( a 42 b ));
}


static void interp_context_boundaries(void) {
  int value = 7;
  List list = %($value(tail));
  List braced_list = %(${value}(tail));
  String text = %"$value()";
  String braced_text = %"${value}()";
  Array array = %[${$(+ 1 2)}];
  Map map = %{answer: ${$(+ 2 3)}};

  EXPECT_LIST_EQ(list, %(7 (tail)));
  EXPECT_LIST_EQ(braced_list, list);
  EXPECT_STR_EQ(text, "7()");
  EXPECT_STR_EQ(braced_text, text);
  EXPECT_INT_EQ(array[0].int(), 3);
  EXPECT_INT_EQ(map[<answer>].int(), 5);
}


static void interp_braced_nested_lisp(void) {
  int direct = $(+ 1 2);
  List braced = %(${$(+ 1 2)});
  EXPECT_INT_EQ(direct, 3);
  EXPECT_LIST_EQ(braced, %(3));
}


static void interp_braced_complete_expression(void) {
  int value = 0;
  List list = %(${value = 1, (int) (value + 1)});
  EXPECT_INT_EQ(value, 1);
  EXPECT_LIST_EQ(list, %(2));
}


static void interp_typed_values_without_var_aliases(void) {
  String string = %"text";
  Symbol symbol = <tag>;
  List nested = %(one two);
  Array array = %[1, 2];
  Map map = %{ key: 3 };
  List values = %($string $symbol $nested $array $map);

  EXPECT_TRUE(values[0].string() === string);
  EXPECT_TRUE(values[1].symbol() == symbol);
  EXPECT_TRUE(values[2].list() === nested);
  EXPECT_TRUE(values[3].array() === array);
  EXPECT_TRUE(values[4].map() === map);
}

static void interp_splice_list(void) {
  List other = %( x y ), lst = %( a @other b );
  EXPECT_LIST_EQ(lst, %( a x y b ));
}

static void interp_splice_var(void) {
  Var v = %( x y );
  List lst = %( a @v b );
  EXPECT_LIST_EQ(lst, %( a x y b ));
}

static Var _interp_splice_call(int list_value) {
  if (list_value) return %( x y );
  return %"not a list";
}

static void interp_splice_var_call(void) {
  List braced = %( a @{_interp_splice_call(1)} b );
  List braced_wrong = %( a @{_interp_splice_call(0)} b );
  EXPECT_LIST_EQ(braced, %( a x y b ));
  EXPECT_LIST_EQ(braced_wrong, %( a b ));
}

static void interp_string_value(void) {
  String x = %"42", s = %"Value: $x";
  EXPECT_STR_EQ(s, "Value: 42");
}

static void interp_string_expr(void) {
  String x = %"42", s = %"Value: ${x}";
  EXPECT_STR_EQ(s, "Value: 42");
}

static void interp_string_numeric_value(void) {
  int x = 42;
  String s = %"Value: $x";
  EXPECT_STR_EQ(s, "Value: 42");
}

static void interp_string_numeric_expr(void) {
  int x = 41;
  String s = %"Value: ${x + 1}";
  EXPECT_STR_EQ(s, "Value: 42");
}


static void interp_string_numeric_source_families(void) {
  char i8 = 'A';
  uchar u8 = 'B';
  short i16 = -12;
  ushort u16 = 13;
  int i32 = -14;
  uint u32 = 15;
  float f32 = 1.25f;
  double f64 = -2.5;

  EXPECT_STR_EQ(%"$i8", "A");
  EXPECT_STR_EQ(%"$u8", "B");
  EXPECT_STR_EQ(%"$i16", "-12");
  EXPECT_STR_EQ(%"$u16", "13");
  EXPECT_STR_EQ(%"$i32", "-14");
  EXPECT_STR_EQ(%"$u32", "15");
  EXPECT_STR_EQ(%"$f32", "1.250000");
  EXPECT_STR_EQ(%"$f64", "-2.500000");
}

// $name and general expression insertion are parsed at separate sites, so
// every converter case below is written for both on purpose.

static void interp_string_symbol_value(void) {
  Symbol symbol = <foo>;
  String s = %"sym: $symbol";
  EXPECT_STR_EQ(s, "sym: foo");
}

static void interp_string_symbol_expr(void) {
  Symbol symbol = <foo>;
  String s = %"sym: ${symbol}";
  EXPECT_STR_EQ(s, "sym: foo");
}

static void interp_string_converter_value(void) {
  Celsius temp = 21;
  String s = %"temp: $temp";
  EXPECT_STR_EQ(s, "temp: C21");
}

static void interp_string_converter_expr(void) {
  Celsius temp = 21;
  String s = %"temp: ${temp}";
  EXPECT_STR_EQ(s, "temp: C21");
}

// A statically typed Var segment renders through Var.str whatever the
// runtime tag turns out to be, so the three tags below all read the way
// the value prints on its own.  Routing the segment through the ordinary
// conversion instead reaches the strict payload extractors, which take
// the String typedef for a pointer and splice Var_pointer.

static void interp_string_var_value(void) {
  Var integer = 5, floating = 3.14, string = %"text";

  EXPECT_STR_EQ(%"v = $integer", "v = 5");
  EXPECT_STR_EQ(%"v = $floating", "v = 3.140000");
  EXPECT_STR_EQ(%"v = $string", "v = text");
}

static void interp_string_var_expr(void) {
  Var integer = 5, floating = 3.14, string = %"text";

  EXPECT_STR_EQ(%"v = ${integer}", "v = 5");
  EXPECT_STR_EQ(%"v = ${floating}", "v = 3.140000");
  EXPECT_STR_EQ(%"v = ${string}", "v = text");
}

static void interp_string_var_alias_value(void) {
  Reading integer = 5, floating = 3.14, string = %"text";

  EXPECT_STR_EQ(%"v = $integer", "v = 5");
  EXPECT_STR_EQ(%"v = $floating", "v = 3.140000");
  EXPECT_STR_EQ(%"v = $string", "v = text");
}

static void interp_string_var_alias_expr(void) {
  Reading integer = 5, floating = 3.14, string = %"text";

  EXPECT_STR_EQ(%"v = ${integer}", "v = 5");
  EXPECT_STR_EQ(%"v = ${floating}", "v = 3.140000");
  EXPECT_STR_EQ(%"v = ${string}", "v = text");
}

$(import "test-macros.xmacro")

void interpolation_suite(void) {
  $test.run(interp_list_value);
  $test.run(interp_list_expr);
  $test.run(interp_context_boundaries);
  $test.run(interp_braced_nested_lisp);
  $test.run(interp_braced_complete_expression);
  $test.run(interp_typed_values_without_var_aliases);
  $test.run(interp_splice_list);
  $test.run(interp_splice_var);
  $test.run(interp_splice_var_call);
  $test.run(interp_string_value);
  $test.run(interp_string_expr);
  $test.run(interp_string_symbol_value);
  $test.run(interp_string_symbol_expr);
  $test.run(interp_string_converter_value);
  $test.run(interp_string_converter_expr);
  $test.run(interp_string_numeric_value);
  $test.run(interp_string_numeric_expr);
  $test.run(interp_string_numeric_source_families);
  $test.run(interp_string_var_value);
  $test.run(interp_string_var_expr);
  $test.run(interp_string_var_alias_value);
  $test.run(interp_string_var_alias_expr);
}
