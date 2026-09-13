/*  test-string.x -- unit tests for string helpers */

#include <ctype.h>
#include <limits.h>
#include <string.h>

#include "test-support.x"

static int _string_test_alpha(char ch) {
  return isalpha((unsigned char) ch);
}

static int _string_test_next(char ch) {
  return ch + 1;
}

static int _string_test_nul(char ch) {
  (void) ch;
  return 0;
}

typedef int (*StringCharFunction)(char);

static int _string_saw_char;

static Var _string_identity_var(Var value) {
  _string_saw_char = value is <i8>;
  return value;
}

static Var _string_truthy_var(Var value) {
  return value.char() == 'a' ? %"truthy" : NULL;
}

static long _string_long_next(char ch) {
  return ch + 1;
}

static Var _string_bad_map(char ch) {
  (void) ch;
  return %"not a number";
}

static Var _string_no_arguments(void) {
  return 1;
}

static Var _string_reference_argument(char &value) {
  return value;
}

static Var _string_raises(char ch) {
  (void) ch;
  raise %(invariant (value 75));
}

static void expect_string_item(List strings, int index, String expected) {
  EXPECT_TRUE(strings.getindex(index).string() == expected);
}

static void string_canonical_identity(void) {
  String first = String.new("canonical identity");
  String second = String.new("canonical identity");
  EXPECT_TRUE(first === second);

  String duplicate = String.malloc(first.len() + 1);
  memcpy(duplicate, first, first.len() + 1);
  EXPECT_TRUE(duplicate !== first);
  EXPECT_TRUE(duplicate.equal(first));
  EXPECT_TRUE(duplicate.intern_free() === first);

  unsigned hash = first.hash();
  EXPECT_INT_EQ(first.hash(), hash);
  String.free(first);
  EXPECT_TRUE(String.new("canonical identity") === first);

  char raw[] = "raw intern input";
  String raw_interned = String.intern(raw);
  EXPECT_TRUE(raw_interned === String.new(raw));
}

static void string_empty_is_native_zero(void) {
  String literal = %"";
  String constructed = String.new("");
  String sized = String.new_len("ignored", 0);
  String allocated = String.malloc(1);
  char *writable = allocated;
  writable[0] = '\0';

  EXPECT_NULL(literal);
  EXPECT_NULL(constructed);
  EXPECT_NULL(sized);
  EXPECT_NULL(allocated.intern_free());
  EXPECT_TRUE(literal.repr() == %"\"\"");
}

static void string_add_and_len(void) {
  String hello = %"hello";
  String world = %"world";
  String joined = String.add(hello, world);
  EXPECT_INT_EQ(joined.len(), 10);
  EXPECT_TRUE(joined == %"helloworld");

  String repeated = String.repeat(%"ab", 3);
  EXPECT_TRUE(repeated == %"ababab");
}

static void string_slice_and_contains(void) {
  String text = %"compiler", mid = text.getslice(1, 4, 1);
  EXPECT_TRUE(mid == %"omp");
  EXPECT_TRUE(text.contains(%"pile"));

  String replaced = text.withindex(0, 'C');
  EXPECT_TRUE(replaced == %"Compiler");
}

static void string_slice_stack_probe_boundaries(void) {
  String text = %"abcdef";
  EXPECT_TRUE(text.getslice(0, 6, 1) === text);
  EXPECT_TRUE(text.getslice(1, 5, 1) == %"bcde");
  EXPECT_TRUE(text.getslice(-4, -1, 1) == %"cdef");
  EXPECT_TRUE(text.getslice(-99, 99, 1) === text);
  EXPECT_NULL(text.getslice(3, 3, 1));
  EXPECT_NULL(text.getslice(4, 2, 1));
  EXPECT_TRUE(text.getslice(0, 6, 2) == %"ace");
  EXPECT_TRUE(text.getslice(5, -7, -2) == %"fdb");

  char raw[259];
  for (int i = 0; i < 258; i++) raw[i] = 'a' + i % 26;
  raw[258] = '\0';

  Pool pool = String.pool_retain_named("string-slice-probe");
  String long_text = String.new_len(raw, 258);
  String at_limit = long_text.getslice(0, 256, 1);
  String over_limit = long_text.getslice(0, 257, 1);
  EXPECT_INT_EQ(at_limit.len(), 256);
  EXPECT_INT_EQ(over_limit.len(), 257);
  EXPECT_INT_EQ(at_limit.getindex(255), raw[255]);
  EXPECT_INT_EQ(over_limit.getindex(256), raw[256]);

  PoolStats after_first = Pool.stats(pool);
  ScopeStats before_hits = Scope.stats();
  EXPECT_TRUE(long_text.getslice(0, 256, 1) === at_limit);
  EXPECT_TRUE(long_text.getslice(0, 256, 1) === at_limit);
  ScopeStats after_hits = Scope.stats();
  PoolStats after_repeat = Pool.stats(pool);
  EXPECT_INT_EQ((int) after_repeat.interned, (int) after_first.interned);
  EXPECT_INT_EQ((int) after_hits.allocation_calls,
                (int) before_hits.allocation_calls);
  String.pool_release();
}

/* String.withindex copy-changes one byte of a canonical String; it must copy
   rather than mutate. Bracket assignment on a String
   is a compile error precisely because an in-place write would corrupt every
   equal String sharing this canonical storage; see the
   string-bracket-assignment compiler fixture. */
static void string_withindex_copies_and_leaves_input_intact(void) {
  String original = %"hello", alias = %"hello";
  EXPECT_TRUE(original == alias);

  String updated = original.withindex(0, 'j');

  EXPECT_TRUE(updated == %"jello");
  EXPECT_TRUE(updated != original);
  EXPECT_TRUE(original == %"hello");
  EXPECT_TRUE(alias == %"hello");
  EXPECT_INT_EQ(original.len(), 5);
  EXPECT_TRUE(original.hash() == String.hash(%"hello"));
  EXPECT_TRUE(updated.hash() == String.hash(%"jello"));

  // A fresh intern of the original content still yields the original bytes.
  EXPECT_TRUE(String.new("hello") == original);

  // Out-of-range indices return the input unchanged rather than mutating.
  EXPECT_TRUE(original.withindex(5, 'x') == original);
  EXPECT_TRUE(original.withindex(-6, 'x') == original);
  EXPECT_TRUE(original == %"hello");
}

static void string_noop_construction_preserves_owner(void) {
  Pool pool = String.pool_retain_named("string-noop-construction");
  String text = %"unchanged";
  String long_text = %"abcdefghij".repeat(30);
  PoolStats before = Pool.stats(pool);

  EXPECT_TRUE(text.repeat(1) === text);
  EXPECT_TRUE(text.withindex(0, 'u') === text);
  EXPECT_TRUE(long_text.getslice(0, long_text.len(), 1) === long_text);
  EXPECT_TRUE(text.replace_n(%"change", %"change", -1) === text);

  PoolStats after = Pool.stats(pool);
  EXPECT_INT_EQ((int) after.allocation_calls,
                (int) before.allocation_calls);

  String transient = String.malloc(text.len() + 1);
  strcpy(transient, text);
  EXPECT_TRUE(transient.repeat(1) === text);
  EXPECT_TRUE(transient.withindex(0, 'u') === text);
  EXPECT_TRUE(transient.getslice(0, transient.len(), 1) === text);
  EXPECT_TRUE(transient.replace_n(%"change", %"change", -1) === text);
  transient.free();
  String.pool_release();
}

static void string_invalid_bytes_transfer(void) {
  int caught = 0;
  try String.new_fill('\0', 3);
  catch %(bad-arg *): caught++;
  try %"abc".withindex(1, '\0');
  catch %(bad-arg *): caught++;
  try %"x".pad_left(3, '\0');
  catch %(bad-arg *): caught++;

  try %"abc".map(_string_test_nul);
  catch %(bad-result *): caught++;

  try String.pool_release();
  catch %(bad-state *): caught++;
  EXPECT_INT_EQ(caught, 5);
}

static void _callback_transfer_round(int measure) {
  ScopeStats before = Scope.stats();
  int caught = 0;
  try %"abc".map(_string_raises);
  catch %(invariant (value ?value)): caught = value.int() == 75;
  ScopeStats after = Scope.stats();
  EXPECT_TRUE(caught);
  if (measure) EXPECT_INT_EQ(after.live_allocations, before.live_allocations);

  before = Scope.stats();
  try %"abc".map(_string_test_nul);
  catch %(bad-result *): caught++;
  after = Scope.stats();
  EXPECT_INT_EQ(caught, 2);
  if (measure) EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
}

/* The first round publishes the catch sites' plans, which `Match` keeps for
   the life of the process; the second measures the steady state. */
static void string_callback_transfer_releases_temporary(void) {
  _callback_transfer_round(0);
  _callback_transfer_round(1);
}

static void string_escape_sequences(void) {
  String esc = %"\x1b[31m";
  EXPECT_INT_EQ(esc.len(), 5);
  EXPECT_INT_EQ(esc.getindex(0), 27);

  String mixed = %"\n\t\\\"";
  EXPECT_INT_EQ(mixed.len(), 4);
  EXPECT_INT_EQ(mixed.getindex(0), '\n');
  EXPECT_INT_EQ(mixed.getindex(1), '\t');
  EXPECT_INT_EQ(mixed.getindex(2), '\\');
  EXPECT_INT_EQ(mixed.getindex(3), '"');

  String doubled = %"a$$b";
  EXPECT_INT_EQ(doubled.len(), 3);
  EXPECT_INT_EQ(doubled.getindex(1), '$');
  EXPECT_INT_EQ(doubled.getindex(2), 'b');

  String escaped_dollar = %"\$value";
  EXPECT_INT_EQ(escaped_dollar.len(), 6);
  EXPECT_INT_EQ(escaped_dollar.getindex(0), '$');

  String hex_runtime = String.unescape(%"\\x41Z");
  EXPECT_INT_EQ(hex_runtime.len(), 2);
  EXPECT_INT_EQ(hex_runtime.getindex(0), 'A');
  EXPECT_INT_EQ(hex_runtime.getindex(1), 'Z');

  String oct_runtime = String.unescape(%"\\7!");
  EXPECT_INT_EQ(oct_runtime.len(), 2);
  EXPECT_INT_EQ(oct_runtime.getindex(0), '\a');
  EXPECT_INT_EQ(oct_runtime.getindex(1), '!');

  EXPECT_INT_EQ(%"'\\x41'".parse_char(), 'A');
  EXPECT_INT_EQ(%"'\\7'".parse_char(), '\a');
}

static void string_multiline_literals(void) {
  String with_newline = %"hello
world";
  EXPECT_INT_EQ(with_newline.len(), 11);
  EXPECT_TRUE(with_newline == %"hello\nworld");

  String continued = %"hello\
world";
  EXPECT_TRUE(continued == %"helloworld");

  List embedded = %("line1
line2");
  Var first = embedded.car();
  EXPECT_TRUE(first.string() == %"line1\nline2");

  List continued_list = %("keep\
going");
  Var continued_first = continued_list.car();
  EXPECT_TRUE(continued_first.string() == %"keepgoing");
}

static void string_boundary_behavior(void) {
  String text = %"abc";
  EXPECT_INT_EQ(text.getindex(3), -1);
  EXPECT_INT_EQ(text.getindex(-1), 'c');
  EXPECT_INT_EQ(text.getindex(-4), -1);
  EXPECT_INT_EQ(text.getindex(99), -1);
  EXPECT_INT_EQ(text.find(%"abc"), 0);
  EXPECT_INT_EQ(text.find(%"bc"), 1);
  EXPECT_INT_EQ(text.find_within(%"bc", 1, -1), 1);
  EXPECT_INT_EQ(text.find_within(%"c", 0, 2), -1);
  EXPECT_TRUE(String.compare(NULL, text) < 0);
  EXPECT_TRUE(text.compare(NULL) > 0);
}

static void string_constructor_invariants(void) {
  EXPECT_NULL(String.malloc(0));
  String bounded = String.new_len("a", 3);
  EXPECT_INT_EQ(bounded.len(), 1);
  EXPECT_INT_EQ(strlen(bounded), 1);

  char embedded[] = {'b', 'c', '\0', 'd', '\0'};
  String truncated = String.new_len(embedded, 4);
  EXPECT_TRUE(truncated == %"bc");
  EXPECT_INT_EQ(truncated.len(), 2);

  String first = String.new_len("order-sensitive", 64);
  String second = String.new("order-sensitive");
  EXPECT_TRUE(first === second);
  EXPECT_INT_EQ(second.len(), 15);

  char long_raw[259];
  for (int i = 0; i < 258; i++) long_raw[i] = 'a' + i % 26;
  long_raw[258] = '\0';
  String long_first = String.new_len(long_raw, 258);
  String long_second = String.new(long_raw);
  EXPECT_INT_EQ(long_first.len(), 258);
  EXPECT_TRUE(long_first === long_second);

  ScopeStats before_free = Scope.stats();
  String transient = String.malloc(4);
  strcpy(transient, "xyz");
  String.free(transient);
  ScopeStats after_free = Scope.stats();
  EXPECT_INT_EQ((int) after_free.live_allocations,
                (int) before_free.live_allocations);

  String oversized = String.malloc(32);
  strcpy(oversized, "short");
  String finalized = oversized.intern_free();
  EXPECT_INT_EQ(finalized.len(), 5);
  EXPECT_TRUE(finalized == %"short");
}

static void string_empty_search_contract(void) {
  String empty = NULL, text = %"abc";
  EXPECT_INT_EQ(text.find(empty), 0);
  EXPECT_INT_EQ(empty.find(empty), 0);
  EXPECT_INT_EQ(text.find_within(empty, -1, -1), 2);
  EXPECT_INT_EQ(text.rfind(empty), 3);
  EXPECT_TRUE(text.contains(empty));
  EXPECT_TRUE(empty.contains(empty));
  EXPECT_TRUE(text.startswith(empty));
  EXPECT_TRUE(text.endswith(empty));
  EXPECT_FALSE(empty.contains(%"a"));
  EXPECT_FALSE(empty.startswith(%"a"));
  EXPECT_FALSE(empty.endswith(%"a"));
  EXPECT_INT_EQ(text.find_all(empty, 0, -1).len(), 0);
  EXPECT_INT_EQ(text.count(empty), 0);
}

static void string_search_and_replace(void) {
  String text = %"abxxabxxab";
  EXPECT_INT_EQ(text.rfind(%"ab"), 8);
  EXPECT_INT_EQ(text.count(%"ab"), 3);
  EXPECT_INT_EQ(%"aaaa".count(%"aa"), 2);
  EXPECT_TRUE(%"aaaa".find_all(%"aa", 0, -1) == %(0 2));
  EXPECT_TRUE(%"ababa".find_all(%"ba", 0, 4) == %(1));
  EXPECT_INT_EQ(%"ababa".find_all(%"ba", 2, -1).car().integer(), 3);
  EXPECT_TRUE(text.replace(%"ab", NULL) == %"xxxx");
  EXPECT_TRUE(text.replace_n(%"ab", %"Q", 2) == %"QxxQxxab");
  EXPECT_TRUE(text.replace_n(%"ab", %"Q", 0) === text);
  EXPECT_TRUE(text.replace_n(NULL, %"Q", -1) === text);
  EXPECT_TRUE(text.replace(%"missing", %"Q") === text);
}

static void string_foreach_bytes_as_int_and_char(void) {
  int total = 0, count = 0;
  foreach(int byte, %"Az") {
    total += byte;
    count++;
  }
  EXPECT_INT_EQ(total, 'A' + 'z');
  EXPECT_INT_EQ(count, 2);

  char first = 0, last = 0;
  foreach(char ch, %"Az") {
    if (!first) first = ch;
    last = ch;
  }
  EXPECT_INT_EQ(first, 'A');
  EXPECT_INT_EQ(last, 'z');

  count = 0;
  foreach(char ch, String.new(NULL)) count += ch;
  EXPECT_INT_EQ(count, 0);
}

static void string_transformations(void) {
  String lower = %"already";
  EXPECT_TRUE(lower.lower() === lower);
  EXPECT_TRUE(%"HeLLo".lower() == %"hello");
  EXPECT_TRUE(%"HeLLo".upper() == %"HELLO");
  EXPECT_TRUE(%"hELLO".capitalize() == %"Hello");
  EXPECT_TRUE(%"  x  ".strip(NULL) == %"x");
  EXPECT_TRUE(%"x".strip(NULL) === %"x");
  EXPECT_TRUE(%"  x  ".lstrip(NULL) == %"x  ");
  EXPECT_TRUE(%"  x  ".rstrip(NULL) == %"  x");
  EXPECT_TRUE(%"xytextyx".lstrip("xy") == %"textyx");
  EXPECT_TRUE(%"xytextyx".rstrip("xy") == %"xytext");
  EXPECT_TRUE(lower.lstrip(NULL) === lower);
  EXPECT_TRUE(lower.rstrip(NULL) === lower);
  EXPECT_NULL(%" \t".lstrip(NULL));
  EXPECT_NULL(%" \t".rstrip(NULL));
  EXPECT_NULL(%"".lstrip(NULL));
  EXPECT_NULL(%"".rstrip(NULL));
  EXPECT_TRUE(String.new_fill('x', 3) == %"xxx");
  EXPECT_NULL(String.new_fill('x', 0));
  EXPECT_TRUE(%"a1b2".filter(_string_test_alpha) == %"ab");
  EXPECT_TRUE(%"abc".map(_string_test_next) == %"bcd");
  EXPECT_NULL(%"abc".keep(NULL));
  EXPECT_TRUE(%"abc".keep(%"ac") == %"ac");
  EXPECT_TRUE(%"abc".reject(NULL) === %"abc");
  EXPECT_TRUE(%"aaabb".squeeze(%"ab") == %"ab");
  EXPECT_NULL(%"abc".repeat(0));
  EXPECT_TRUE(%"ab".repeat(2) == %"abab");
}

static void string_func_callbacks(void) {
  StringCharFunction alpha_pointer = _string_test_alpha;
  StringCharFunction next_pointer = _string_test_next;
  char rejected = 'b';
  int shift = 1;
  Func captured_filter = %!(char ch) => ch != rejected;
  Func captured_map = %!(char ch) => ch + shift;

  EXPECT_TRUE(%"a1b2".filter(alpha_pointer) == %"ab");
  EXPECT_TRUE(%"abc".filter(captured_filter) == %"ac");
  EXPECT_TRUE(%"abc".filter(_string_truthy_var) == %"a");
  EXPECT_TRUE(%"abc".map(next_pointer) == %"bcd");
  EXPECT_TRUE(%"abc".map(captured_map) == %"bcd");
  EXPECT_TRUE(%"abc".map(_string_long_next) == %"bcd");
  _string_saw_char = 0;
  EXPECT_TRUE(%"a".map(_string_identity_var) == %"a");
  EXPECT_TRUE(_string_saw_char);
  // the reported defect: a callback reading its <i8> box through int()
  Func int_reader_map = %!(Var ch) => ch.int() + shift;
  EXPECT_TRUE(%"abc".map(int_reader_map) == %"bcd");
}

static void string_func_rejects_invalid_callbacks_on_invocation(void) {
  Func wrong_arity = _string_no_arguments;
  Func reference = _string_reference_argument;
  int arity_caught = 0, reference_caught = 0, conversion_caught = 0;

  try %"abc".filter(wrong_arity);
  catch %(bad-arity *): arity_caught++;
  try %"abc".map(reference);
  catch %(bad-types *): reference_caught++;
  try %"abc".map(_string_bad_map);
  catch %(no-convert *): conversion_caught++;
  EXPECT_INT_EQ(arity_caught, 1);
  EXPECT_INT_EQ(reference_caught, 1);
  EXPECT_INT_EQ(conversion_caught, 1);

  String empty = NULL;
  EXPECT_NULL(empty.filter(wrong_arity));
  EXPECT_NULL(empty.map(wrong_arity));
  EXPECT_TRUE(%"abc".filter(NULL) === %"abc");
  EXPECT_TRUE(%"abc".map(NULL) === %"abc");
}

static void string_byte_escaping(void) {
  char raw[] = {(char) 0x80, (char) 0xff, '\0'};
  String bytes = String.new_len(raw, 2), escaped = bytes.escape();
  EXPECT_STR_EQ(escaped, "\\200\\377");
  EXPECT_TRUE(escaped.unescape() == bytes);
  EXPECT_INT_EQ(%"'\\0'".parse_char(), 0);

  char mixed_raw[] = {'A', '"', '\'', '\\', '\n', '\t',
                      (char) 0x80, '\0'};
  String mixed = String.new_len(mixed_raw, 7);
  Buffer out = Buffer.new(0);
  mixed.write_repr(out);
  EXPECT_TRUE(out.str_free() == %"\"%s\"".printf(mixed.escape()));
}

static void string_padding_removal_and_partition(void) {
  EXPECT_TRUE(%"x".pad_left(3, '-') == %"--x");
  EXPECT_TRUE(%"x".pad_right(3, '-') == %"x--");
  EXPECT_TRUE(%"abc".pad_center(6, '-') == %"-abc--");
  EXPECT_TRUE(String.pad_left(NULL, 3, ' ') == %"   ");
  EXPECT_TRUE(%"wide".pad_left(2, '-') === %"wide");

  String path = %"prefix-body-suffix";
  EXPECT_TRUE(path.remove_prefix(%"prefix-") == %"body-suffix");
  EXPECT_TRUE(path.remove_suffix(%"-suffix") == %"prefix-body");
  EXPECT_TRUE(path.remove_prefix(%"missing") === path);
  EXPECT_TRUE(path.remove_suffix(NULL) === path);

  List parts = %"a=b=c".partition(%"=");
  EXPECT_INT_EQ(parts.len(), 3);
  expect_string_item(parts, 0, %"a");
  expect_string_item(parts, 1, %"=");
  expect_string_item(parts, 2, %"b=c");

  List right = %"a=b=c".rpartition(%"=");
  expect_string_item(right, 0, %"a=b");
  expect_string_item(right, 1, %"=");
  expect_string_item(right, 2, %"c");

  List missing = %"abc".partition(%"=");
  expect_string_item(missing, 0, %"abc");
  expect_string_item(missing, 1, NULL);
  expect_string_item(missing, 2, NULL);

  List empty = %"abc".rpartition(NULL);
  expect_string_item(empty, 0, NULL);
  expect_string_item(empty, 1, NULL);
  expect_string_item(empty, 2, %"abc");
}

$(import "test-macros.xmacro")

void string_suite(void) {
  $test.run(string_canonical_identity);
  $test.run(string_empty_is_native_zero);
  $test.run(string_add_and_len);
  $test.run(string_slice_and_contains);
  $test.run(string_slice_stack_probe_boundaries);
  $test.run(string_withindex_copies_and_leaves_input_intact);
  $test.run(string_noop_construction_preserves_owner);
  $test.run(string_invalid_bytes_transfer);
  $test.run(string_callback_transfer_releases_temporary);
  $test.run(string_escape_sequences);
  $test.run(string_multiline_literals);
  $test.run(string_boundary_behavior);
  $test.run(string_constructor_invariants);
  $test.run(string_empty_search_contract);
  $test.run(string_search_and_replace);
  $test.run(string_foreach_bytes_as_int_and_char);
  $test.run(string_transformations);
  $test.run(string_func_callbacks);
  $test.run(string_func_rejects_invalid_callbacks_on_invocation);
  $test.run(string_byte_escaping);
  $test.run(string_padding_removal_and_partition);
}
