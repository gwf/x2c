/*  test-component-input-raw.x -- Component ownership and ordered raw dispatch. */

import "x2cui" with Ui, Offscreen;
#include "test-support.x"
#include "../../../unittest/test-macros.x"

typedef struct RouteState {
  int calls, repeats;
  bool handled;
} RouteState;

static bool route(Ui ui, void *user, const cui_input_event *event) {
  RouteState *state = user;
  state.calls++;
  if (event.kind == CUI_INPUT_KEY && cui_input_repeated(ui)) state.repeats++;
  return state.handled;
}

static void canvas(Ui ui, const char *name, bool component) {
  int flags = CUI_CANVAS_FOCUSABLE | (component ? CUI_CANVAS_COMPONENT_INPUT : 0);
  cui_canvas_ex(ui, name, CUI_PX(100), CUI_PX(40), NULL, NULL, 0, flags);
}

static void ownership(void) {
  Offscreen screen = auto Offscreen.open(300, 200);
  Ui ui = screen.ui();
  cui_id first = ui.make_id("first"), ordinary = ui.make_id("ordinary");
  ui.begin_frame(0);
  canvas(ui, "first", true);
  canvas(ui, "ordinary", false);
  cui_request_component_focus(ui, first);
  ui.end_frame();
  EXPECT_TRUE(cui_component_has_input(ui, first));
  EXPECT_TRUE(cui_focused_id(ui) == first);

  // Removing participation also revokes ownership, even if the ID remains.
  ui.begin_frame(0);
  canvas(ui, "first", false);
  canvas(ui, "ordinary", false);
  ui.end_frame();
  EXPECT_FALSE(cui_component_has_input(ui, first));
  EXPECT_TRUE(cui_focused_id(ui) == 0);
  ui.begin_frame(0);
  canvas(ui, "first", true);
  canvas(ui, "ordinary", false);
  cui_request_component_focus(ui, first);
  ui.end_frame();

  // A submitted ordinary canvas is not a component-focus request target.
  ui.begin_frame(0);
  canvas(ui, "first", true);
  canvas(ui, "ordinary", false);
  cui_request_component_focus(ui, ordinary);
  ui.end_frame();
  EXPECT_TRUE(cui_focused_id(ui) == first);
  EXPECT_FALSE(cui_component_has_input(ui, ordinary));

  // The absent request expires rather than acquiring a later appearance.
  ui.begin_frame(0);
  canvas(ui, "ordinary", false);
  cui_request_component_focus(ui, first);
  ui.end_frame();
  EXPECT_FALSE(cui_component_has_input(ui, first));
  ui.begin_frame(0);
  canvas(ui, "first", true);
  canvas(ui, "ordinary", false);
  ui.end_frame();
  EXPECT_FALSE(cui_component_has_input(ui, first));

  ui.begin_frame(0);
  canvas(ui, "first", true);
  cui_request_component_focus(ui, first);
  ui.end_frame();
  ui.begin_frame(0);
  cui_push_disabled(ui, true);
  canvas(ui, "first", true);
  cui_pop_disabled(ui);
  cui_request_component_focus(ui, first);
  ui.end_frame();
  EXPECT_FALSE(cui_component_has_input(ui, first));
}

static void physical_and_actions(void) {
  Offscreen screen = auto Offscreen.open(300, 200);
  Ui ui = screen.ui();
  RouteState state = {.handled = true};
  cui_input_event event = {.kind = CUI_INPUT_KEY, .key = CUI_KEY_SPACE, .down = true};
  ui.begin_frame(0);
  cui_dispatch_input(ui, &event, route, &state);
  EXPECT_TRUE(cui_key_down(ui, CUI_KEY_SPACE));
  EXPECT_FALSE(cui_key_action_down(ui, CUI_KEY_SPACE));
  EXPECT_FALSE(cui_key_pressed(ui, CUI_KEY_SPACE));
  cui_dispatch_input(ui, &event, route, &state);
  EXPECT_INT_EQ(state.repeats, 1);
  event.down = false;
  cui_dispatch_input(ui, &event, route, &state);
  EXPECT_FALSE(cui_key_down(ui, CUI_KEY_SPACE));
  EXPECT_FALSE(cui_key_action_down(ui, CUI_KEY_SPACE));
  ui.end_frame();

  ui.begin_frame(0);
  event = (cui_input_event){.kind = CUI_INPUT_FOCUS, .focused = false};
  cui_dispatch_input(ui, &event, route, &state);
  int calls = state.calls;
  event = (cui_input_event){.kind = CUI_INPUT_KEY, .key = CUI_KEY_SPACE, .down = true};
  cui_dispatch_input(ui, &event, route, &state);
  EXPECT_FALSE(cui_window_focused(ui));
  EXPECT_INT_EQ(state.calls, calls);
  EXPECT_TRUE(cui_key_down(ui, CUI_KEY_SPACE));
  EXPECT_FALSE(cui_key_action_down(ui, CUI_KEY_SPACE));
  event = (cui_input_event){.kind = CUI_INPUT_FOCUS, .focused = true};
  cui_dispatch_input(ui, &event, route, &state);
  EXPECT_FALSE(cui_key_action_down(ui, CUI_KEY_SPACE));
  event = (cui_input_event){.kind = CUI_INPUT_KEY, .key = CUI_KEY_SPACE, .down = false};
  cui_dispatch_input(ui, &event, route, &state);
  state.handled = false;
  event.down = true;
  cui_dispatch_input(ui, &event, route, &state);
  EXPECT_TRUE(cui_key_action_down(ui, CUI_KEY_SPACE));
  EXPECT_TRUE(cui_key_pressed(ui, CUI_KEY_SPACE));
  ui.end_frame();

  // A direct legacy blur also cancels an opt-in consumed hold.
  ui.begin_frame(0);
  state.handled = true;
  cui_dispatch_input(ui, &event, route, &state);
  cui_input_focus(ui, false);
  cui_input_focus(ui, true);
  cui_input_key(ui, CUI_KEY_SPACE, true, 0);
  EXPECT_TRUE(cui_key_action_down(ui, CUI_KEY_SPACE));
  ui.end_frame();
}

static void fallback_tab(void) {
  Offscreen screen = auto Offscreen.open(300, 200);
  Ui ui = screen.ui();
  cui_id first = ui.make_id("first"), second = ui.make_id("second");
  ui.begin_frame(0);
  canvas(ui, "first", true);
  canvas(ui, "second", true);
  cui_request_component_focus(ui, first);
  ui.end_frame();
  RouteState state = {0};
  cui_input_event event = {.kind = CUI_INPUT_KEY, .key = CUI_KEY_TAB, .down = true};
  ui.begin_frame(0);
  cui_dispatch_input(ui, &event, route, &state);
  canvas(ui, "first", true);
  canvas(ui, "second", true);
  ui.end_frame();
  EXPECT_TRUE(cui_component_has_input(ui, second));
  ui.begin_frame(0);
  canvas(ui, "first", true);
  canvas(ui, "second", true);
  ui.end_frame();
  EXPECT_TRUE(cui_component_has_input(ui, second));
}

typedef struct PopupInput {
  bool modal_open, open_popup, request;
  char text[32];
  cui_id component, unrelated;
  bool focus_unrelated, check_previous;
} PopupInput;

static void popup_input_frame(Ui ui, PopupInput *state) {
  cui_begin_frame(ui, 0);
  if (state.check_previous) EXPECT_TRUE(cui_component_has_input(ui, state.component));
  cui_button_ex(ui, "Outside anchor", NULL);
  if (state.open_popup) cui_popover_open(ui, "Unrelated popup");
  if (cui_popover_begin(ui, "Unrelated popup", NULL)) {
    state.unrelated = cui_make_id(ui, "unrelated");
    canvas(ui, "unrelated", true);
    if (state.focus_unrelated) cui_request_component_focus(ui, state.unrelated);
    cui_popover_end(ui);
  }
  if (cui_dialog_begin(ui, "Modal", &state.modal_open, NULL)) {
    cui_button_ex(ui, "Anchor", NULL);
    if (state.open_popup) cui_popover_open(ui, "Popup");
    if (cui_popover_begin(ui, "Popup", NULL)) {
      cui_input_ex(ui, "builtin", state.text, sizeof state.text,
                   &(cui_input_opts){.autofocus = true});
      state.component = cui_make_id(ui, "component");
      canvas(ui, "component", true);
      if (state.request) cui_request_component_focus(ui, state.component);
      cui_popover_end(ui);
    }
    cui_dialog_end(ui);
  }
  cui_end_frame(ui);
  state.open_popup = false;
}

static void modal_popup_input(void) {
  Offscreen screen = auto Offscreen.open(640, 480);
  Ui ui = screen.ui();
  cui_set_reduced_motion(ui, true);
  PopupInput state = {.modal_open = true, .open_popup = true};
  popup_input_frame(ui, &state);
  cui_input_text(ui, "X");
  popup_input_frame(ui, &state);
  EXPECT_STR_EQ(state.text, "X");
  state.request = true;
  popup_input_frame(ui, &state);
  EXPECT_TRUE(cui_focused_id(ui) == state.component);
  EXPECT_TRUE(cui_component_has_input(ui, state.component));
  state.request = false;
  state.check_previous = true;
  state.focus_unrelated = true;
  popup_input_frame(ui, &state);
  EXPECT_TRUE(cui_focused_id(ui) == state.unrelated);
  EXPECT_FALSE(cui_component_has_input(ui, state.unrelated));
}

static void raw_component_suite(void) {
  $test.run(ownership);
  $test.run(physical_and_actions);
  $test.run(fallback_tab);
  $test.run(modal_popup_input);
}

int main(void) {
  TestHarness_begin();
  $test.suite(raw_component_suite);
  return TestHarness_finish();
}
