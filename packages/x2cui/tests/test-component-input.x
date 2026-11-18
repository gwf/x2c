/*  test-component-input.x -- ordinary component input and callback errors */
import "x2cui" with Offscreen, Ui;
#include "test-support.x"
#include "../../../unittest/test-macros.x"

typedef struct Counter { cui_id id; int value; } Counter;

static bool counter_input(Ui ui, void *user, const cui_input_event *event) {
  Counter *counter = user;
  if (!ui.component_has_input(counter.id)) return false;
  if (event.kind != CUI_INPUT_KEY || !event.down) return false;
  if (event.key != CUI_KEY_UP) return false;
  counter.value++;
  return true;
}

static void submit_counter(Offscreen screen, Counter *counter) {
  Ui ui = screen.ui();
  counter.id = ui.make_id("counter");
  ui.canvas_input("counter", fill, 60, NULL, NULL, 0);
  screen.end();
}

static void component_handles_keys_without_text(void) {
  Offscreen screen = auto Offscreen.open(320, 100);
  Ui ui = screen.ui();
  Counter counter = {};
  screen.begin();
  submit_counter(screen, &counter);
  ui.request_component_focus(counter.id);
  screen.begin();
  submit_counter(screen, &counter);
  EXPECT_TRUE(ui.component_has_input(counter.id));
  cui_input_event event = { .kind = CUI_INPUT_KEY, .key = CUI_KEY_UP, .down = true };
  screen.begin();
  ui.dispatch_input(&event, counter_input, &counter);
  EXPECT_INT_EQ(counter.value, 1);
  EXPECT_TRUE(ui.key_down(up));
  EXPECT_FALSE(ui.key_action_down(up));
  submit_counter(screen, &counter);
  event.down = false;
  screen.begin();
  ui.dispatch_input(&event, counter_input, &counter);
  EXPECT_FALSE(ui.key_down(up));
  submit_counter(screen, &counter);
}

static bool failed_input(Ui ui, void *user, const cui_input_event *event) {
  raise %(input-fail (operation "component route"));
  return false;
}

static void callback_error_returns_from_cui_before_raising(void) {
  Offscreen screen = auto Offscreen.open(320, 100);
  Ui ui = screen.ui();
  cui_input_event event = { .kind = CUI_INPUT_KEY, .key = CUI_KEY_SPACE, .down = true };
  screen.begin();
  bool caught = false;
  try ui.dispatch_input(&event, failed_input, NULL);
  catch %(input-fail *detail): caught = true;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(ui.key_down(space));
  EXPECT_FALSE(ui.key_action_down(space));
  screen.end();
  event.down = false;
  screen.begin();
  ui.dispatch_input(&event, NULL, NULL);
  EXPECT_FALSE(ui.key_down(space));
  screen.end();
}

int main(void) {
  TestHarness_begin();
  $test.run(component_handles_keys_without_text);
  $test.run(callback_error_returns_from_cui_before_raising);
  return TestHarness_finish();
}
