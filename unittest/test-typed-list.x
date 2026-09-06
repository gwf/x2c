/*  test-typed-list.x -- typed cons chain tests */

#include "typed-list.x"
#include "list-selectors.x"
#include "test-support.x"
$(import "test-macros.xmacro")

static int _typed_list_odd(Var value) {
  return value.integer() % 2;
}

static void typed_list_shares_canonical_cells(void) {
  $test.scoped();
  ListInt values = %(1 2 3);
  List plain = %(1 2 3);

  /* The converter retypes rather than copies, so the typed chain and the
     literal that spells it are one value. */
  EXPECT_TRUE((void *) values == (void *) plain);
  EXPECT_INT_EQ(values.len(), 3);

  ListInt tail = %(2 3);
  EXPECT_TRUE((void *) ListInt.cons(1, tail) == (void *) plain);
}

static void typed_list_reads_elements_natively(void) {
  $test.scoped();
  ListInt values = %(4 5 6);

  EXPECT_INT_EQ(values.car(), 4);
  EXPECT_INT_EQ(values.cdr().car(), 5);
  EXPECT_INT_EQ(values.cddr().car(), 6);
  EXPECT_INT_EQ(values.last(), 6);
  EXPECT_INT_EQ(values.index(6), 2);
  EXPECT_INT_EQ(values.nth_cdr(2).car(), 6);
}

static void typed_list_reads_nil_as_zero(void) {
  $test.scoped();

  /* car of nil is void, whose bits are all ones, so the guard decides the
     answer rather than merely avoiding a null read. */
  EXPECT_INT_EQ(ListInt.car(NULL), 0);
  EXPECT_INT_EQ(ListShort.car(NULL), 0);
  EXPECT_TRUE(ListDbl.car(NULL) == 0.0);
  EXPECT_TRUE(ListString.car(NULL) == NULL);
  EXPECT_TRUE(ListChar.car(NULL) == 0);
}

static void typed_list_structural_results_stay_typed(void) {
  $test.scoped();
  ListInt values = %(1 2 3);

  EXPECT_INT_EQ(values.reverse().car(), 3);
  EXPECT_INT_EQ(values.getslice(1, 3, 1).car(), 2);
  EXPECT_INT_EQ(values.subseq(0, 2, 1).last(), 2);
  EXPECT_INT_EQ(values.head(2).last(), 2);
  EXPECT_INT_EQ(values.tail(2).car(), 2);
  EXPECT_INT_EQ(values.append(values).len(), 6);

  ListInt sorted = %(3 1 2);
  EXPECT_INT_EQ(sorted.sort().car(), 1);
  ListInt repeated = %(1 1 2);
  EXPECT_INT_EQ(repeated.unique().len(), 2);
}

static void typed_list_remaining_receiver_relative_methods(void) {
  $test.scoped();
  ListInt values = %(1 2 3 4 5);

  EXPECT_INT_EQ(values.cdddr().car(), 4);
  EXPECT_INT_EQ(values.cddddr().car(), 5);
  EXPECT_TRUE((void *) values.promote() == (void *) values);

  ListInt selected = values.filter(_typed_list_odd);
  EXPECT_INT_EQ(selected.len(), 3);
  EXPECT_INT_EQ(selected.car(), 1);
  EXPECT_INT_EQ(selected.last(), 5);

  ListInt flattened = values.flatten();
  ListInt flattened_all = values.flatten_all();
  EXPECT_INT_EQ(flattened.len(), 5);
  EXPECT_INT_EQ(flattened_all.last(), 5);
}

static void typed_list_walks_without_reconverting(void) {
  $test.scoped();
  ListInt values = %(1 2 3 4);

  /* cdr returns the typed spelling, so the loop assignment needs no
     converter and the walk stays linear. */
  int walked = 0, total = 0;
  for (ListInt cursor = values; cursor; cursor = cursor.cdr()) {
    walked++;
    total += cursor.car();
  }
  EXPECT_INT_EQ(walked, 4);
  EXPECT_INT_EQ(total, 10);
}

static void typed_list_iterates_as_elements(void) {
  $test.scoped();
  ListInt values = %(2 4 6);

  int total = 0;
  foreach(int value, values) total += value;
  EXPECT_INT_EQ(total, 12);

  ListDbl reals = %(0.5 1.5);
  double sum = 0.0;
  foreach(double value, reals) sum += value;
  EXPECT_TRUE(sum == 2.0);
}

static void typed_list_covers_every_family(void) {
  $test.scoped();
  ListChar letters =
    ListChar.cons('a', ListChar.cons('z', NULL));
  ListShort shorts =
    ListShort.cons(-3, ListShort.cons(-7, NULL));
  ListInt integers = %(3 4);
  ListFloat reals = %(1.5f 2.5f);
  ListDbl doubles = %(1.5 2.5);
  ListString words = %("alpha" "beta");
  ListSymbol names = %(alpha beta);

  EXPECT_TRUE(letters.cdr().car() == 'z');
  EXPECT_INT_EQ(shorts.cdr().car(), -7);
  EXPECT_INT_EQ(integers.cdr().car(), 4);
  EXPECT_TRUE(reals.cdr().car() == 2.5f);
  EXPECT_TRUE(doubles.cdr().car() == 2.5);
  EXPECT_TRUE(words.cdr().car() == %"beta");
  EXPECT_TRUE(names.cdr().car() == <beta>);
}

static void _expect_typed_list_common(
  List values, List later, Array array,
  String direct_str, String direct_repr, unsigned direct_hash,
  Buffer streamed_str, Buffer streamed_repr, int comparison) {
  EXPECT_STR_EQ(direct_str, values.str());
  EXPECT_STR_EQ(direct_repr, values.repr());
  EXPECT_INT_EQ(direct_hash, values.hash());
  EXPECT_STR_EQ(streamed_str.str(), values.str());
  EXPECT_STR_EQ(streamed_repr.str(), values.repr());
  EXPECT_TRUE(comparison < 0);
  EXPECT_TRUE(values.compare(later) < 0);
  EXPECT_INT_EQ(array.len(), values.len());

  Var boxed = values;
  EXPECT_STR_EQ(boxed.str(), values.str());
  EXPECT_STR_EQ(boxed.repr(), values.repr());
  EXPECT_INT_EQ(boxed.hash(), values.hash());
  EXPECT_TRUE(boxed.compare(later) < 0);
}

static void typed_list_common_capabilities_cover_every_family(void) {
  $test.scoped();

  ListChar chars = ListChar.cons(1, ListChar.cons(2, NULL));
  ListChar later_chars = ListChar.cons(1, ListChar.cons(3, NULL));
  Buffer char_str = Buffer.new(0), char_repr = Buffer.new(0);
  chars.write_str(char_str); chars.write_repr(char_repr);
  _expect_typed_list_common(
    chars, later_chars, chars.array(), chars.str(), chars.repr(), chars.hash(),
    char_str, char_repr, chars.compare(later_chars));

  ListShort shorts = ListShort.cons(10, ListShort.cons(20, NULL));
  ListShort later_shorts = ListShort.cons(10, ListShort.cons(30, NULL));
  Buffer short_str = Buffer.new(0), short_repr = Buffer.new(0);
  shorts.write_str(short_str); shorts.write_repr(short_repr);
  _expect_typed_list_common(
    shorts, later_shorts, shorts.array(), shorts.str(), shorts.repr(),
    shorts.hash(), short_str, short_repr, shorts.compare(later_shorts));

  ListInt ints = %(100 200), later_ints = %(100 300);
  Buffer int_str = Buffer.new(0), int_repr = Buffer.new(0);
  ints.write_str(int_str); ints.write_repr(int_repr);
  _expect_typed_list_common(
    ints, later_ints, ints.array(), ints.str(), ints.repr(), ints.hash(),
    int_str, int_repr, ints.compare(later_ints));

  ListFloat floats = %(1.5f 2.5f), later_floats = %(1.5f 3.5f);
  Buffer float_str = Buffer.new(0), float_repr = Buffer.new(0);
  floats.write_str(float_str); floats.write_repr(float_repr);
  _expect_typed_list_common(
    floats, later_floats, floats.array(), floats.str(), floats.repr(),
    floats.hash(), float_str, float_repr, floats.compare(later_floats));

  ListDbl doubles = %(1.5 2.5), later_doubles = %(1.5 3.5);
  Buffer double_str = Buffer.new(0), double_repr = Buffer.new(0);
  doubles.write_str(double_str); doubles.write_repr(double_repr);
  _expect_typed_list_common(
    doubles, later_doubles, doubles.array(), doubles.str(), doubles.repr(),
    doubles.hash(), double_str, double_repr, doubles.compare(later_doubles));

  ListString strings = %("alpha" "one");
  ListString later_strings = %("alpha" "two");
  Buffer string_str = Buffer.new(0), string_repr = Buffer.new(0);
  strings.write_str(string_str); strings.write_repr(string_repr);
  _expect_typed_list_common(
    strings, later_strings, strings.array(), strings.str(), strings.repr(),
    strings.hash(), string_str, string_repr, strings.compare(later_strings));

  ListSymbol symbols = %(alpha one), later_symbols = %(alpha two);
  Buffer symbol_str = Buffer.new(0), symbol_repr = Buffer.new(0);
  symbols.write_str(symbol_str); symbols.write_repr(symbol_repr);
  _expect_typed_list_common(
    symbols, later_symbols, symbols.array(), symbols.str(), symbols.repr(),
    symbols.hash(), symbol_str, symbol_repr, symbols.compare(later_symbols));
}

static void typed_list_widens_for_var_transforms(void) {
  $test.scoped();
  ListInt values = %(1 2 3);

  /* Operations whose callbacks can replace elements have no typed spelling;
     widening is how a caller reaches them. */
  List widened = values;
  EXPECT_INT_EQ(widened.len(), 3);
  EXPECT_TRUE(widened.str() == %"( 1 2 3 )");
}

static void typed_list_converts_through_var(void) {
  $test.scoped();
  ListInt values = %(7 8);

  Var boxed = values;
  EXPECT_TRUE(boxed is <list>);
  EXPECT_INT_EQ(boxed.listint().car(), 7);
}

static void typed_list_rejects_foreign_elements(void) {
  $test.scoped();
  int caught = 0;

  try {
    List mixed = %(1 "two");
    ListInt values = mixed;
    EXPECT_INT_EQ(values.car(), 1);
  }
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 1);

  try {
    List nested = %(1 (2 3));
    ListInt values = nested;
    EXPECT_INT_EQ(values.car(), 1);
  }
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 2);

  /* The tags neighbour each other in the Var encoding, so check both
     directions rather than trusting one. */
  try {
    List integers = %(1 2);
    ListDbl reals = integers;
    EXPECT_TRUE(reals.car() == 1.0);
  }
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 3);

  try {
    List reals = %(1.5 2.5);
    ListInt integers = reals;
    EXPECT_INT_EQ(integers.car(), 1);
  }
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 4);

  try {
    ListInt integers = %(1 2);
    List mixed = %(3 "four");
    ListInt joined = integers.append(mixed);
    EXPECT_INT_EQ(joined.len(), 4);
  }
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 5);
}

static void typed_list_accepts_nil_for_every_family(void) {
  $test.scoped();
  List empty = %();

  ListInt integers = empty;
  ListString words = empty;
  EXPECT_TRUE((void *) integers == NULL);
  EXPECT_TRUE((void *) words == NULL);
  EXPECT_INT_EQ(integers.len(), 0);
}

void typed_list_suite(void) {
  $test.run(typed_list_shares_canonical_cells);
  $test.run(typed_list_reads_elements_natively);
  $test.run(typed_list_reads_nil_as_zero);
  $test.run(typed_list_structural_results_stay_typed);
  $test.run(typed_list_remaining_receiver_relative_methods);
  $test.run(typed_list_walks_without_reconverting);
  $test.run(typed_list_iterates_as_elements);
  $test.run(typed_list_covers_every_family);
  $test.run(typed_list_common_capabilities_cover_every_family);
  $test.run(typed_list_widens_for_var_transforms);
  $test.run(typed_list_converts_through_var);
  $test.run(typed_list_rejects_foreign_elements);
  $test.run(typed_list_accepts_nil_for_every_family);
}
