/*  test-raw-api.x -- direct calls through the pinned termbox2 header. */

#include "termbox2-2.5.h"
#include "test-support.x"
#include <string.h>

$(import "../../../unittest/test-macros.xmacro")

static void raw_profile_and_status(void) {
  EXPECT_STR_EQ(String.new((char *) tb_version()), %"2.5.0");
  EXPECT_INT_EQ(tb_attr_width(), 64);
  EXPECT_TRUE(tb_has_egc());
  EXPECT_INT_EQ(tb_width(), TB_ERR_NOT_INIT);
  EXPECT_STR_EQ(
    String.new((char *) tb_strerror(TB_ERR_OUT_OF_BOUNDS)),
    %"Out of bounds"
  );
}

static void raw_representative_surface(void) {
  EXPECT_NOT_NULL((void *) tb_init_rwfd);
  EXPECT_NOT_NULL((void *) tb_get_fds);
  EXPECT_NOT_NULL((void *) tb_set_cell_ex);
  EXPECT_NOT_NULL((void *) tb_peek_event);
  EXPECT_NOT_NULL((void *) tb_set_func);
  EXPECT_NOT_NULL((void *) tb_sendf);
}

static void raw_utf8_utilities(void) {
  uint32_t character = 0;
  EXPECT_INT_EQ(tb_utf8_char_to_unicode(&character, "\xce\xbb"), 2);
  EXPECT_INT_EQ(character, 0x03bb);

  char bytes[8] = { 0 };
  EXPECT_INT_EQ(tb_utf8_unicode_to_char(bytes, character), 2);
  EXPECT_TRUE(!memcmp(bytes, "\xce\xbb", 2));
}

void termbox2_raw_suite(void) {
  $test.run(raw_profile_and_status);
  $test.run(raw_representative_surface);
  $test.run(raw_utf8_utilities);
}

int main(void) {
  TestHarness_begin();
  $test.suite(termbox2_raw_suite);
  return TestHarness_finish();
}
