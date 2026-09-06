/*  test-raw-api.x -- Direct PCRE2-8 and POSIX escape-hatch smoke test. */

#include "pcre2-posix.h"
#include "test-support.x"
#include <string.h>

$(import "../../../unittest/test-macros.xmacro")

static void pcre2_raw_core(void) {
  char version[32] = { 0 };
  EXPECT_TRUE(pcre2_config(PCRE2_CONFIG_VERSION, version) >= 0);
  EXPECT_TRUE(!strncmp(version, "10.48", 5));

  int error_code = 0;
  PCRE2_SIZE error_offset = 0;
  pcre2_code *code = pcre2_compile(
    (PCRE2_SPTR) "(?<word>[a-z]+)", PCRE2_ZERO_TERMINATED, 0,
    &error_code, &error_offset, NULL
  );
  EXPECT_NOT_NULL(code);
  if (!code) return;
  defer pcre2_code_free(code);

  uint32_t captures = 0;
  EXPECT_INT_EQ(
    pcre2_pattern_info(code, PCRE2_INFO_CAPTURECOUNT, &captures), 0
  );
  EXPECT_INT_EQ(captures, 1);
  EXPECT_NOT_NULL((void *) pcre2_match_8);
}

static void pcre2_raw_posix(void) {
  regex_t regex = { 0 };
  EXPECT_INT_EQ(regcomp(&regex, "([a-z]+)-([0-9]+)", 0), 0);
  defer regfree(&regex);

  regmatch_t matches[3] = { 0 };
  EXPECT_INT_EQ(regexec(&regex, "item-42", 3, matches, 0), 0);
  EXPECT_INT_EQ(matches[1].rm_so, 0);
  EXPECT_INT_EQ(matches[1].rm_eo, 4);

  char message[128] = { 0 };
  EXPECT_TRUE(regerror(REG_BADPAT, &regex, message, sizeof(message)) > 0);
  EXPECT_TRUE(message[0] != '\0');
}

void pcre2_raw_suite(void) {
  $test.run(pcre2_raw_core);
  $test.run(pcre2_raw_posix);
}

int main(void) {
  TestHarness_begin();
  $test.suite(pcre2_raw_suite);
  return TestHarness_finish();
}
