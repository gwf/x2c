/*  test-string-number.x -- unit tests for String numeric parsing */

#include "test-support.x"
#include <limits.h>

static void string_numeric_parsing(void) {
  long integer = 99;
  EXPECT_TRUE(%"0".try_long(&integer));
  EXPECT_INT_EQ(integer, 0);
  EXPECT_TRUE(%"42".try_long(&integer));
  EXPECT_INT_EQ(integer, 42);
  EXPECT_TRUE(%"  -0b101".try_long(&integer));
  EXPECT_INT_EQ(integer, -5);
  EXPECT_TRUE(%"+0o17".try_long(&integer));
  EXPECT_INT_EQ(integer, 15);
  EXPECT_TRUE(%"077".try_long(&integer));
  EXPECT_INT_EQ(integer, 63);
  EXPECT_TRUE(%"0x2a".try_long(&integer));
  EXPECT_INT_EQ(integer, 42);
  integer = 77;
  EXPECT_FALSE(%"".try_long(&integer));
  EXPECT_INT_EQ(integer, 77);
  EXPECT_FALSE(%"   ".try_long(&integer));
  EXPECT_INT_EQ(integer, 77);
  EXPECT_FALSE(%"nope".try_long(&integer));
  EXPECT_INT_EQ(integer, 77);
  EXPECT_FALSE(%"999999999999999999999999999999".try_long(&integer));

  double floating = 9.0;
  EXPECT_TRUE(%"0".try_double(&floating));
  EXPECT_TRUE(floating == 0.0);
  EXPECT_TRUE(%"1.25".try_double(&floating));
  EXPECT_TRUE(floating > 1.249 && floating < 1.251);
  floating = 7.0;
  EXPECT_FALSE(%"bad".try_double(&floating));
  EXPECT_TRUE(floating == 7.0);
  EXPECT_FALSE(%"".try_double(&floating));
  EXPECT_TRUE(floating == 7.0);
  EXPECT_FALSE(%"   ".try_double(&floating));
  EXPECT_TRUE(floating == 7.0);
}

/* The try_ readers must consume the whole string; only whitespace may follow
   the number. Each rejection also proves the out-parameter is untouched. */
static void string_numeric_readers_are_exact(void) {
  long integer = 5;
  EXPECT_FALSE(%"42junk".try_long(&integer));
  EXPECT_INT_EQ(integer, 5);
  EXPECT_FALSE(%"  -0b101tail".try_long(&integer));
  EXPECT_INT_EQ(integer, 5);
  EXPECT_FALSE(%"+0o17rest".try_long(&integer));
  EXPECT_INT_EQ(integer, 5);
  EXPECT_FALSE(%"077suffix".try_long(&integer));
  EXPECT_INT_EQ(integer, 5);
  EXPECT_FALSE(%"42 43".try_long(&integer));
  EXPECT_INT_EQ(integer, 5);
  EXPECT_TRUE(%"  42  ".try_long(&integer));
  EXPECT_INT_EQ(integer, 42);
  EXPECT_TRUE(%"42\t\n".try_long(&integer));
  EXPECT_INT_EQ(integer, 42);

  double floating = 4.0;
  EXPECT_FALSE(%"1.5junk".try_double(&floating));
  EXPECT_TRUE(floating == 4.0);
  EXPECT_FALSE(%"  1.25tail".try_double(&floating));
  EXPECT_TRUE(floating == 4.0);
  // strtod knows no 0o or 0b prefix, so it consumes only the leading zero
  // and the rest is now trailing junk rather than a silent 0 result.
  EXPECT_FALSE(%"0b101".try_double(&floating));
  EXPECT_TRUE(floating == 4.0);
  EXPECT_TRUE(%"  1.25 ".try_double(&floating));
  EXPECT_TRUE(floating > 1.249 && floating < 1.251);
}

/* strtod spellings and range behavior, which the exact reader inherits. */
static void string_numeric_double_edges(void) {
  double floating = 0.0;
  EXPECT_TRUE(%"0x1p4".try_double(&floating));
  EXPECT_TRUE(floating == 16.0);
  EXPECT_TRUE(%"inf".try_double(&floating));
  EXPECT_TRUE(floating > 0.0 && floating * 2.0 == floating);
  EXPECT_TRUE(%"nan".try_double(&floating));
  EXPECT_TRUE(floating != floating);
  floating = 3.0;
  EXPECT_FALSE(%"1e400".try_double(&floating));
  EXPECT_TRUE(floating == 3.0);
  EXPECT_FALSE(%"1e-400".try_double(&floating));
  EXPECT_TRUE(floating == 3.0);

  long integer = 8;
  EXPECT_TRUE(%"-9223372036854775808".try_long(&integer));
  EXPECT_TRUE(integer == LONG_MIN);
  EXPECT_TRUE(%"9223372036854775807".try_long(&integer));
  EXPECT_TRUE(integer == LONG_MAX);
  EXPECT_FALSE(%"99999999999999999999".try_long(&integer));
  EXPECT_TRUE(integer == LONG_MAX);
}

$(import "test-macros.xmacro")

void string_number_suite(void) {
  $test.run(string_numeric_parsing);
  $test.run(string_numeric_readers_are_exact);
  $test.run(string_numeric_double_edges);
}
