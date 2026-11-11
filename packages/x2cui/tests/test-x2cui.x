/*  test-x2cui.x -- Focused tests for the x2c surface over CUI.

    Every test draws off screen with the software renderer and drives
    components through CUI's own input functions, so none needs a window.
*/

import "x2cui" with App, Offscreen, TextField, Ui;

#include "path.x"
#include "test-support.x"

#include "../../../unittest/test-macros.x"

// What one frame of the form below reports.
typedef struct Form {
  bool agree;
  int tab;
  TextField name;
  int clicks;
  int typed;
  cui_rect button;
  cui_rect box;
  cui_rect field;
} Form;

static void draw_form(Ui ui, Form &form) {
  $cui.column(ui, { .pad = 16, .gap = 12, .width = CUI_FILL }) {
    form.clicks += ui.button("Save", { .variant = CUI_BUTTON_PRIMARY });
    form.button = ui.last_rect();
    ui.checkbox("I agree", form.agree, {});
    form.box = ui.last_rect();
    form.typed |= ui.input("name", form.name, { .width = CUI_FILL });
    form.field = ui.last_rect();
    ui.segmented("tab", %("One" "Two" "Three"), form.tab, {});
  }
}

static void frame(Offscreen screen, Form &form) {
  screen.begin();
  draw_form(screen.ui(), form);
  screen.end();
}

// Presses and releases the left button at the centre of `target`.
static void click(Offscreen screen, Form &form, cui_rect target) {
  Ui ui = screen.ui();
  ui.input_mouse_move(target.x + target.w / 2, target.y + target.h / 2);
  frame(screen, form);
  ui.input_mouse_button(CUI_MOUSE_LEFT, true);
  frame(screen, form);
  ui.input_mouse_button(CUI_MOUSE_LEFT, false);
  frame(screen, form);
  frame(screen, form);
}

static void offscreen_draws_and_writes_a_png(void) {
  Form form = { .name = TextField.new(32) };
  Offscreen screen = auto Offscreen.open(320, 240);
  frame(screen, form);
  EXPECT_TRUE(screen.commands() > 0);

  Path directory = Path.temp_dir();
  Path image = directory.join("form.png");
  screen.write_png(image);
  unsigned char head[8] = { 0 };
  FILE *file = fopen(image, "rb");
  EXPECT_NOT_NULL(file);
  if (file) {
    EXPECT_INT_EQ(fread(head, 1, sizeof head, file), 8);
    fclose(file);
  }
  EXPECT_INT_EQ(memcmp(head, "\x89PNG\r\n\x1a\n", 8), 0);
  directory.remove_tree();
}

static void write_png_raises_io_failure(void) {
  Form form = { .name = TextField.new(32) };
  Offscreen screen = auto Offscreen.open(64, 64);
  frame(screen, form);
  int refused = 0;
  try screen.write_png("/no-such-directory/x2cui/form.png");
  catch %(io-fail *detail): refused = 1;
  EXPECT_INT_EQ(refused, 1);
}

static void closing_nothing_returns_null(void) {
  Offscreen none = NULL;
  EXPECT_NULL(none.close());
  App window = NULL;
  EXPECT_NULL(window.close());
}

static void a_click_reaches_a_button_and_a_reference(void) {
  Form form = { .name = TextField.new(32) };
  Offscreen screen = auto Offscreen.open(320, 240);
  frame(screen, form);
  frame(screen, form);
  EXPECT_INT_EQ(form.clicks, 0);
  EXPECT_FALSE(form.agree);

  click(screen, form, form.button);
  EXPECT_INT_EQ(form.clicks, 1);

  // The checkbox writes through its reference parameter.
  click(screen, form, form.box);
  EXPECT_TRUE(form.agree);
}

static void typed_text_reaches_a_text_field(void) {
  Form form = { .name = TextField.new(8) };
  Offscreen screen = auto Offscreen.open(320, 240);
  frame(screen, form);
  frame(screen, form);
  EXPECT_TRUE(form.name.empty());

  click(screen, form, form.field);
  screen.ui().input_text("Ada");
  frame(screen, form);
  frame(screen, form);
  EXPECT_STR_EQ(form.name.text(), "Ada");
  EXPECT_TRUE(form.typed & CUI_CHANGED);

  // The field's capacity bounds what a component can write.
  screen.ui().input_text(" Lovelace");
  frame(screen, form);
  frame(screen, form);
  EXPECT_INT_EQ(form.name.text().len(), 7);
}

static void a_text_field_sets_and_takes_text(void) {
  TextField field = TextField.new(8);
  EXPECT_TRUE(field.empty());
  field.set("abc");
  EXPECT_STR_EQ(field.text(), "abc");
  field.set("longer than eight");
  EXPECT_STR_EQ(field.text(), "longer ");
  EXPECT_STR_EQ(field.take(), "longer ");
  EXPECT_TRUE(field.empty());
}

// A block left early must still end, or CUI's layout stack is unbalanced.
static int draw_rows(Ui ui, int stop_at) {
  for (int i = 0; i < 4; i++) {
    $cui.id_index(ui, i) $cui.row(ui, { .gap = 4 }) {
      if (i == 1) continue;
      if (i == stop_at) return i;
      ui.label(%"row $i");
    }
  }
  return -1;
}

static void a_block_left_early_still_ends(void) {
  Offscreen screen = auto Offscreen.open(200, 200);
  int stopped = 0;
  for (int pass = 0; pass < 3; pass++) {
    screen.begin();
    $cui.column(screen.ui(), { .gap = 4 }) {
      stopped = draw_rows(screen.ui(), 2);
      screen.ui().label("after the rows");
    }
    screen.end();
  }
  EXPECT_INT_EQ(stopped, 2);
  // "row 0" and "after the rows" drew; the frame ended without a fault.
  EXPECT_TRUE(screen.commands() > 0);
}

static void a_text_result_is_a_string(void) {
  Offscreen screen = auto Offscreen.open(64, 64);
  screen.begin();
  String every = screen.ui().cron_describe("*/5 * * * *");
  screen.end();
  EXPECT_TRUE(every.len() > 0);
}

static void a_string_list_reaches_a_component(void) {
  Offscreen screen = auto Offscreen.open(320, 120);
  int crumb = 0;
  for (int pass = 0; pass < 2; pass++) {
    screen.begin();
    crumb = screen.ui().breadcrumb(%("Home" "Projects" "x2c"));
    screen.end();
  }
  EXPECT_INT_EQ(crumb, -1);
  EXPECT_TRUE(screen.commands() > 0);
}

void x2cui_suite(void) {
  $test.run(offscreen_draws_and_writes_a_png);
  $test.run(write_png_raises_io_failure);
  $test.run(closing_nothing_returns_null);
  $test.run(a_click_reaches_a_button_and_a_reference);
  $test.run(typed_text_reaches_a_text_field);
  $test.run(a_text_field_sets_and_takes_text);
  $test.run(a_block_left_early_still_ends);
  $test.run(a_text_result_is_a_string);
  $test.run(a_string_list_reaches_a_component);
}

int main(void) {
  TestHarness_begin();
  $test.suite(x2cui_suite);
  return TestHarness_finish();
}
