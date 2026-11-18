/*  test-experimental.x -- clipboard, wheel routing, and voice samples */

import "x2cui" with Offscreen, Ui, voice_resample;

#include "test-support.x"
#include "../../../unittest/test-macros.x"

static char clipboard[64];
static void set_clipboard(void *user, const char *text) {
  snprintf(clipboard, sizeof clipboard, "%s", text);
}
static const char *get_clipboard(void *user) => clipboard;

static void clipboard_uses_platform_hooks(void) {
  Offscreen screen = auto Offscreen.open(200, 100);
  Ui ui = screen.ui();
  cui_platform_iface platform = {
    .set_clipboard = set_clipboard, .get_clipboard = get_clipboard };
  ui.set_platform(platform);
  ui.set_clipboard_text("experimental clipboard");
  String saved = ui.get_clipboard_text();
  EXPECT_STR_EQ(saved, "experimental clipboard");
  ui.set_clipboard_text("changed");
  EXPECT_STR_EQ(saved, "experimental clipboard");
  EXPECT_STR_EQ(ui.get_clipboard_text(), "changed");
  cui_platform_iface empty = {};
  ui.set_platform(empty);
  ui.set_clipboard_text("ignored");
  EXPECT_TRUE(ui.get_clipboard_text().len() == 0);
}

static void voice_resampling_keeps_peaks(void) {
  ArrayFloat levels = [0.1f, 0.8f, 0.2f, 0.6f];
  ArrayFloat peaks = voice_resample(levels, 2);
  EXPECT_INT_EQ(peaks.len(), 2);
  EXPECT_TRUE(peaks[0] == 0.8f && peaks[1] == 0.6f);
  peaks[0] = 0;
  EXPECT_TRUE(levels[1] == 0.8f);
  EXPECT_INT_EQ(voice_resample(levels, 0).len(), 0);
}

static void paint_wheel(Ui ui, cui_rect rect, void *data) {
  ui.wheel_region(*(cui_id *) data, rect);
}

static bool wheel_frame(Offscreen screen, cui_vec2 &delta) {
  screen.begin();
  Ui ui = screen.ui();
  cui_id id = ui.make_id("wheel-region");
  bool taken = ui.wheel_take(id, delta);
  ui.canvas("canvas", 180, 80, paint_wheel, &id, sizeof id);
  screen.end();
  return taken;
}

static void canvas_consumes_both_wheel_axes_once(void) {
  Offscreen screen = auto Offscreen.open(200, 100);
  cui_vec2 delta = {};
  wheel_frame(screen, delta);
  screen.ui().input_mouse_move(50, 40);
  wheel_frame(screen, delta);
  screen.ui().input_scroll(0.5f, -1);
  EXPECT_TRUE(wheel_frame(screen, delta));
  EXPECT_TRUE(delta.x == 0.5f && delta.y == -1);
  EXPECT_FALSE(wheel_frame(screen, delta));
}

int main(void) {
  TestHarness_begin();
  $test.run(clipboard_uses_platform_hooks);
  $test.run(voice_resampling_keeps_peaks);
  $test.run(canvas_consumes_both_wheel_axes_once);
  return TestHarness_finish();
}
