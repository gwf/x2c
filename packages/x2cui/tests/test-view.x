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
               (segmented ((bind tab)) \"tabs\" (\"Only\"))
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
  // The search skips List arguments such as the labels.
  EXPECT_TRUE(((List) lisp.eval_string("(ui-find ui 'absent)")).len() == 0);
}

static String text(Lisp lisp, String name) {
  Var value = void;
  EXPECT_TRUE(lisp.try_get(name, value));
  return value;
}

static void a_message_goes_up_to_the_first_handler(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  lisp.eval_string("(def log \"\")");
  lisp.eval_string(
    "(def note (lambda (who what) (def log (ui-text log who what))))");
  View view = start(lisp, %"
    (def ui
      '(column ((pad 20) (on save (lambda (what) (note \"outer:\" what))))
         (row ((on save (lambda (what) (note \"inner:\" what))))
           (button ((width 120) (on-click (send save \"a\"))) \"Save\"))))");
  click(screen, view, 40, 36);
  EXPECT_STR_EQ(text(lisp, "log"), "inner:a");
}

static void a_handler_passes_and_sends(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  lisp.eval_string("(def log \"\")");
  lisp.eval_string("(def note (lambda (what) (def log (ui-text log what))))");
  // A lambda has one body form; `then` evaluates two in order.
  lisp.eval_string("(def then (lambda (first second) second))");
  View view = start(lisp, %"
    (def ui
      '(column ((pad 20)
                (on save (lambda ()
                  (then (note \"outer \") (ui-send 'done 7))))
                (on done (lambda (n) (note n))))
         (row ((on save (lambda () (then (note \"inner \") (ui-pass)))))
           (button ((width 120) (on-click (send save))) \"Save\")
           (button ((width 120) (on-click (send unheard))) \"Other\"))))");
  click(screen, view, 40, 36);
  EXPECT_STR_EQ(text(lisp, "log"), "inner outer 7");
  // A message no node handles is dropped.
  click(screen, view, 170, 36);
  EXPECT_STR_EQ(text(lisp, "log"), "inner outer 7");
  bool caught = false;
  try lisp.eval_string("(ui-pass)");
  catch %(bad-state *detail): caught = true;
  EXPECT_TRUE(caught);
}

static void cards_draw_the_child_their_option_names(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  lisp.eval_string("(def page 'first)");
  lisp.eval_string("(def seen \"\")");
  View view = start(lisp, %"
    (def ui
      '(column ((pad 20))
         (cards ((show (eval page)))
           (button ((id first) (width 120)
                    (on-click (lambda () (def page 'second)))) \"Next\")
           (button ((id second) (width 120)
                    (on-click (lambda () (def seen \"second\"))))
                   \"Here\"))))");
  click(screen, view, 40, 36);
  EXPECT_STR_EQ(text(lisp, "seen"), "");
  click(screen, view, 40, 36);
  EXPECT_STR_EQ(text(lisp, "seen"), "second");
  // The tree functions look inside cards as inside any block.
  List second = lisp.eval_string("(ui-find ui 'second)");
  EXPECT_STR_EQ((String) second[2], "Here");
}

typedef struct Seen { Ui ui; int nodes; cui_id button, row, text; } Seen;

static void see(void *user, List node, cui_id id) {
  Seen *seen = user;
  seen.nodes++;
  if (node[0] == <button>) seen.button = id;
  if (node[0] == <row>) seen.row = id;
  if (node[0] == <text>) seen.text = id;
}

static void a_watcher_learns_each_node_and_its_id(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  View view = start(lisp, %"
    (def ui '(column ((pad 20)) (row () (text () \"a\")
                                        (button ((width 120)) \"Add\"))))");
  Seen seen = { .ui = screen.ui() };
  view.watch(see, &seen);
  frame(screen, view);
  EXPECT_INT_EQ(seen.nodes, 4);
  frame(screen, view);
  cui_rect button = screen.ui().get_rect(seen.button);
  EXPECT_INT_EQ((int) button.w, 120);
  EXPECT_TRUE(button.x > 20 && button.y >= 20);
  // A block is found by an id the view gives it while it is watched.
  cui_rect row = screen.ui().get_rect(seen.row);
  EXPECT_TRUE(row.w >= button.w && row.h >= button.h);
  // Text has no id in CUI; the view draws it in a box that has one.
  cui_rect text = screen.ui().get_rect(seen.text);
  EXPECT_TRUE(text.w > 0 && text.x < button.x);
  view.watch(NULL, NULL);
  frame(screen, view);
  EXPECT_INT_EQ(seen.nodes, 8);
}

static void a_watched_block_with_no_children_has_a_size(void) {
  Lisp lisp = auto Lisp.new();
  Offscreen screen = auto Offscreen.open(320, 200);
  View view = start(lisp, "(def ui '(column ((pad 20)) (row ())))");
  Seen seen = { .ui = screen.ui() };
  view.watch(see, &seen);
  frame(screen, view);
  frame(screen, view);
  cui_rect row = screen.ui().get_rect(seen.row);
  EXPECT_TRUE(row.w >= 72);
  EXPECT_INT_EQ((int) row.h, 32);
}

static void the_component_table_describes_each_component(void) {
  List button = View.components().find(%!(List row) => row[0] == "button");
  EXPECT_NOT_NULL(button);
  EXPECT_INT_EQ((int) button[1], 0);
  EXPECT_STR_EQ(((List) button[2]).repr(), "((\"label\" \"text\"))");
  List options = button[3];
  List variant = options.find(%!(List row) => row[0] == "variant");
  EXPECT_STR_EQ((String) variant[1], "enum");
  EXPECT_TRUE("primary" in variant);
  List width = options.find(%!(List row) => row[0] == "width");
  EXPECT_STR_EQ((String) width[1], "size");
  List row = View.components().find(%!(List row) => row[0] == "row");
  EXPECT_INT_EQ((int) row[1], 1);
  List slider = View.components().find(%!(List row) => row[0] == "slider");
  EXPECT_STR_EQ(((List) slider[2]).repr(),
    "((\"label\" \"text\") (\"value\" \"bound\") "
    "(\"min\" \"number\") (\"max\" \"number\"))");
}

int main(void) {
  TestHarness_begin();
  $test.run(a_click_runs_the_handler_once);
  $test.run(a_handler_replaces_part_of_the_tree);
  $test.run(a_bound_component_keeps_its_value_in_a_global);
  $test.run(a_bound_input_edits_the_text_of_a_global);
  $test.run(a_misspelled_option_raises_and_closes_its_blocks);
  $test.run(options_convert_by_the_type_of_their_field);
  $test.run(a_message_goes_up_to_the_first_handler);
  $test.run(a_handler_passes_and_sends);
  $test.run(cards_draw_the_child_their_option_names);
  $test.run(a_watcher_learns_each_node_and_its_id);
  $test.run(a_watched_block_with_no_children_has_a_size);
  $test.run(the_component_table_describes_each_component);
  return TestHarness_finish();
}
