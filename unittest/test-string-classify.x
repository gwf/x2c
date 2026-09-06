/*  test-string-classify.x -- unit tests for String byte classification */

#include "test-support.x"

static void string_classification(void) {
  char raw[] = {(char) 0x80, (char) 0xff, '\0'};
  String bytes = String.new_len(raw, 2);

  EXPECT_TRUE(%"alpha".is_alpha());
  EXPECT_TRUE(%"alpha_beta".is_alpha_under());
  EXPECT_TRUE(%"123".is_digit());
  EXPECT_TRUE(%"a1".contains_digit());
  EXPECT_FALSE(%"abc".contains_digit());
  EXPECT_TRUE(%"a1".is_alnum());
  EXPECT_TRUE(%"a_1".is_alnum_under());
  EXPECT_TRUE(%"_name1".is_identifier());
  EXPECT_TRUE(%" \t\n".is_space());
  EXPECT_TRUE(%"lower".is_lower());
  EXPECT_TRUE(%"lower_under".is_lower_under());
  EXPECT_TRUE(%"UPPER".is_upper());
  EXPECT_TRUE(%"UPPER_UNDER".is_upper_under());
  EXPECT_FALSE(bytes.is_alpha());
}

$(import "test-macros.xmacro")

void string_classify_suite(void) {
  $test.run(string_classification);
}
