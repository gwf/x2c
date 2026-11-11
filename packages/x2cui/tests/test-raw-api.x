/*  test-raw-api.x -- The pinned CUI API reached through the package.

    The package publishes src/cui-1.3.h, so importing it is enough to call
    upstream declarations under their own names, including the ones the
    client never wraps.
*/

import "x2cui" with Ui;

#include "test-support.x"

#include "../../../unittest/test-macros.x"

static void cui_raw_header(void) {
  EXPECT_INT_EQ(CUI_VERSION_MAJOR, 1);
  EXPECT_INT_EQ(CUI_VERSION_MINOR, 3);

  cui_sw_renderer *renderer = cui_sw_create();
  defer cui_sw_destroy(renderer);
  cui_ctx *ui = cui_create(
    &(cui_ctx_desc){ .renderer = cui_sw_iface(renderer) });
  defer cui_destroy(ui);
  EXPECT_NOT_NULL(ui);
  cui_set_viewport(ui, 240, 120, 1);

  bool agree = false;
  cui_begin_frame(ui, 1.0f / 60);
  cui_column_begin(ui, &(cui_box){ .pad = 8, .gap = 8 });
  // The variadic text function has no method and stays a raw call.
  cui_textf(ui, "%d of %d", 2, 3);
  cui_button_ex(ui, "Save", &(cui_button_opts){ .icon = CUI_ICON_CHECK });
  cui_checkbox_ex(ui, "I agree", &agree, NULL);
  cui_box_end(ui);
  cui_end_frame(ui);

  const cui_draw_data *data = cui_get_draw_data(ui);
  EXPECT_TRUE(data.command_count > 0);
  EXPECT_INT_EQ(data.width_px, 240);

  // A Ui is the same pointer, so raw calls and methods mix freely.
  Ui same = ui;
  EXPECT_TRUE(same.viewport_size().x == 240);

  // The window layer's declarations are present; no window is opened.
  EXPECT_NOT_NULL((void *) cui_app_create);
  EXPECT_NOT_NULL((void *) cui_app_frame);
}

void cui_raw_suite(void) {
  $test.run(cui_raw_header);
}

int main(void) {
  TestHarness_begin();
  $test.suite(cui_raw_suite);
  return TestHarness_finish();
}
