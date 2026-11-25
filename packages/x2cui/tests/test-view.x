/*  test-view.x -- a UI held as a List, drawn off screen and driven by
    CUI's own input functions. */
import "x2cui" with Offscreen, Ui, View, ViewLisp;
#include "test-support.x"
#include "../../../unittest/test-macros.x"

static void frame(Offscreen screen, View view) {
  screen.begin();
  view.draw(screen.ui());
  screen.end();
}

// Presses and releases the left button at `x`, `y`.
static void click(Offscreen screen, View view, float x, float y) {
  Ui ui = screen.ui();
  ui.input_mouse_move(x, y);
  frame(screen, view);
  ui.input_mouse_button(left, true);
  frame(screen, view);
  ui.input_mouse_button(left, false);
  frame(screen, view);
  frame(screen, view);
}

static View start(Lisp lisp, String source) {
  ViewLisp.install(lisp);
  lisp.eval_string(source);
  return View.new(lisp, "ui");
}

static double number(Lisp lisp, String name) {
  Var value = void;
  EXPECT_TRUE(lisp.try_get(name, value));
  return value.double();
}

static void a_click_runs_the_handler_once(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  lisp.eval_string("(def clicks 0)");
  lisp.eval_string("(def bump (lambda () (def clicks (+ clicks 1))))");
  View view = start(lisp, %"
    (def ui '(column ((pad 20) (gap 12))
               (button ((variant primary) (width 120) (on-click bump)) \"Add\")
               (text () (eval (ui-text \"Clicked \" clicks)))))");
  frame(screen, view);
  EXPECT_TRUE(screen.commands() > 0);
  click(screen, view, 40, 36);
  EXPECT_INT_EQ((int) number(lisp, "clicks"), 1);
  click(screen, view, 40, 36);
  EXPECT_INT_EQ((int) number(lisp, "clicks"), 2);
}

static void a_handler_replaces_part_of_the_tree(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  View view = start(lisp, %"
    (def ui '(column ((pad 20))
               (button ((width 120)
                        (on-click (lambda ()
                          (def ui (ui-replace ui 'note
                                    '(text ((id note)) \"after\"))))))
                       \"Swap\")
               (text ((id note)) \"before\")))");
  frame(screen, view);
  List note = lisp.eval_string("(ui-find ui 'note)");
  EXPECT_STR_EQ((String) note[2], "before");
  click(screen, view, 40, 36);
  note = lisp.eval_string("(ui-find ui 'note)");
  EXPECT_STR_EQ((String) note[2], "after");
  frame(screen, view);
}

static void a_bound_component_keeps_its_value_in_a_global(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  lisp.eval_string("(def agree 0)");
  lisp.eval_string("(def changes 0)");
  View view = start(lisp, %"
    (def ui '(column ((pad 20))
               (checkbox ((bind agree)
                          (on-change (lambda () (def changes (+ changes 1)))))
                         \"I agree\")))");
  click(screen, view, 30, 30);
  EXPECT_INT_EQ((int) number(lisp, "agree"), 1);
  EXPECT_INT_EQ((int) number(lisp, "changes"), 1);
  lisp.eval_string("(def agree 0)");
  frame(screen, view);
  EXPECT_INT_EQ((int) number(lisp, "agree"), 0);
}

static void a_bound_input_edits_the_text_of_a_global(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  lisp.eval_string("(def name \"Ada\")");
  View view = start(lisp, %"
    (def ui '(column ((pad 20)) (input ((bind name) (width 200)) \"name\")))");
  click(screen, view, 60, 36);
  screen.ui().input_text("!");
  frame(screen, view);
  frame(screen, view);
  Var name = void;
  EXPECT_TRUE(lisp.try_get("name", name));
  EXPECT_STR_EQ((String) name, "Ada!");
}

static void a_misspelled_option_raises_and_closes_its_blocks(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  View view = start(lisp, %"
    (def ui '(column ((pad 20)) (row () (button ((colour 1)) \"Add\"))))");
  bool caught = false;
  screen.begin();
  try view.draw(screen.ui());
  catch %(bad-arg *detail): caught = true;
  screen.end();
  EXPECT_TRUE(caught);
  lisp.eval_string("(def ui '(column ((pad 20)) (nothing () \"x\")))");
  caught = false;
  screen.begin();
  try view.draw(screen.ui());
  catch %(bad-arg *detail): caught = true;
  screen.end();
  EXPECT_TRUE(caught);
  lisp.eval_string("(def ui '(column ((pad 20)) (button () \"Add\")))");
  frame(screen, view);
  EXPECT_TRUE(screen.commands() > 0);
}

static void options_convert_by_the_type_of_their_field(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  lisp.eval_string("(def level 0.25)");
  lisp.eval_string("(def tab 1)");
  View view = start(lisp, %"
    (def ui '(column ((pad 20) (gap 8) (min_width 200) (align center))
               (row ((gap 8) (width fill) (justify between))
                 (badge ((tone success)) \"ok\")
                 (button ((width (grow 2)) (size sm) (disabled 1)) \"Wide\"))
               (slider ((bind level) (width fill)) \"Level\" 0 1)
               (segmented ((bind tab)) \"tabs\" (\"One\" \"Two\" \"Three\"))
               (progress ((height 6)) (eval level))
               (separator ())
               (heading () \"Title\" 2)))");
  frame(screen, view);
  frame(screen, view);
  EXPECT_TRUE(screen.commands() > 0);
  EXPECT_INT_EQ((int) number(lisp, "tab"), 1);
  // A List argument, such as the labels, is searched but is no node.
  EXPECT_TRUE(((List) lisp.eval_string("(ui-find ui 'absent)")).len() == 0);
}

int main(void) {
  TestHarness_begin();
  $test.run(a_click_runs_the_handler_once);
  $test.run(a_handler_replaces_part_of_the_tree);
  $test.run(a_bound_component_keeps_its_value_in_a_global);
  $test.run(a_bound_input_edits_the_text_of_a_global);
  $test.run(a_misspelled_option_raises_and_closes_its_blocks);
  $test.run(options_convert_by_the_type_of_their_field);
  return TestHarness_finish();
}
