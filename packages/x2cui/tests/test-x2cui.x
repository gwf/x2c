/*  test-x2cui.x -- Focused tests for the x2c surface over CUI.

    Every test draws off screen with the software renderer and drives
    components through CUI's own input functions, so none needs a window.
*/

import "x2cui" with App, Offscreen, RowState, TextField, Ui, x2cui_strings;

#include <malloc/malloc.h>

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
  ui.column (pad: 16, gap: 12, width: fill) {
    form.clicks += ui.button("Save", variant: primary);
    form.button = ui.last_rect();
    ui.checkbox("I agree", form.agree);
    form.box = ui.last_rect();
    form.typed |= ui.input("name", form.name, width: fill);
    form.field = ui.last_rect();
    ui.segmented("tab", %("One" "Two" "Three"), form.tab);
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
  ui.input_mouse_button(left, true);
  frame(screen, form);
  ui.input_mouse_button(left, false);
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
    ui.id (i) ui.row (gap: 4) {
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
    screen.ui().column (gap: 4) {
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

/* CUI reads a wheel picker's items when it paints, after the call that
   passed them has returned. */
static void a_string_list_lasts_until_the_frame_is_painted(void) {
  Offscreen screen = auto Offscreen.open(240, 240);
  int month = 1;
  for (int pass = 0; pass < 4; pass++) {
    screen.begin();
    // The first array is built inside a region, which must not free it.
    if (pass == 0) auto {
      screen.ui().wheel_picker(
        "month", %("January" "February" "March"), month);
    }
    else
      screen.ui().wheel_picker(
        "month", %("January" "February" "March"), month);
    screen.end();
  }
  EXPECT_TRUE(screen.commands() > 0);
  EXPECT_INT_EQ(month, 1);
}

/* A method that formats takes x2c values after its format. The terminal
   buffer keeps the text it was given. */
static void formatted_text_takes_x2c_values(void) {
  char text[128];
  cui_terminal_line lines[4];
  cui_terminal_buffer terminal;
  cui_terminal_init(&terminal, text, sizeof text, lines, 4);
  String unit = "ms";
  terminal.printf("%d of %d in %.1f %s", 2, 3, 4.25, unit);
  String written = String.new_len(terminal.text, terminal.end);
  EXPECT_STR_EQ(written, "2 of 3 in 4.2 ms");

  Offscreen screen = auto Offscreen.open(240, 64);
  screen.begin();
  screen.ui().textf("%d of %d", 2, 3);
  screen.end();
  EXPECT_TRUE(screen.commands() > 0);
}

// Bytes the default malloc zone holds in use.
static size_t bytes_in_use(void) {
  malloc_statistics_t stats;
  malloc_zone_statistics(NULL, &stats);
  return stats.size_in_use;
}

/* The empty List and a List converted before allocate nothing, and a
   List's array holds its Strings. */
static void string_lists_convert_once(void) {
  List labels = %("One" "Two");
  const char *const *names = x2cui_strings(labels);
  EXPECT_STR_EQ(names[1], "Two");
  x2cui_strings(%());
  size_t before = bytes_in_use();
  for (int i = 0; i < 100000; i++) {
    x2cui_strings(%());
    x2cui_strings(labels);
  }
  EXPECT_INT_EQ(bytes_in_use() - before, 0);
  EXPECT_TRUE(x2cui_strings(labels) == names);
}

// method forms

// Draws three frames of `draw` and writes the last to `path`.
static void shoot(String path, void (*draw)(Ui ui)) {
  Offscreen screen = auto Offscreen.open(360, 240);
  for (int pass = 0; pass < 3; pass++) {
    screen.begin();
    draw(screen.ui());
    screen.end();
  }
  screen.write_png(path);
}

// Whether `draw` and `expected` draw the same pixels.
static bool same_pixels(void (*draw)(Ui ui), void (*expected)(Ui ui)) {
  Path directory = Path.temp_dir();
  defer directory.remove_tree();
  Path one = directory.join("one.png"), two = directory.join("two.png");
  shoot(one, draw);
  shoot(two, expected);
  FILE *a = fopen(one, "rb"), *b = fopen(two, "rb");
  defer { fclose(a); fclose(b); }
  int x, y;
  do {
    x = fgetc(a);
    y = fgetc(b);
  } while (x == y && x != EOF);
  return x == y;
}

/* Short names, numbers, `grow`, `?:`, a declared name, and NULL, each
   lowered by the type of its field or parameter. */
static void short_forms(Ui ui) {
  int variant = CUI_BUTTON_DANGER;
  bool wide = true;
  ui.column (width: fill, pad: 12, gap: 8, bg: surface_muted) {
    ui.row (gap: 8, align: center) {
      ui.button("Add", variant: primary, icon: plus);
      ui.icon_button(x, variant: ghost, size: sm);
      ui.box (width: grow(2)) ui.text("wide", font: wide ? medium : body,
                                     color: accent);
      ui.box (width: 30, height: 10, bg: border) {}
    }
    ui.button("Declared", variant: variant, tooltip: NULL);
    ui.text("plain");
  }
}

// The same screen in CUI's own C calls, which the method forms wrap.
static void c_forms(Ui ui) {
  cui_column_begin(ui, &(cui_box){ .width = CUI_FILL, .pad = 12, .gap = 8,
                                   .bg = CUI_COLOR_SURFACE_MUTED });
  cui_row_begin(ui, &(cui_box){ .gap = 8, .align = CUI_ALIGN_CENTER });
  cui_button_ex(ui, "Add", &(cui_button_opts){
    .variant = CUI_BUTTON_PRIMARY, .icon = CUI_ICON_PLUS });
  cui_icon_button_ex(ui, CUI_ICON_X, &(cui_button_opts){
    .variant = CUI_BUTTON_GHOST, .size = CUI_SIZE_SM });
  cui_box_begin(ui, &(cui_box){ .width = CUI_GROW(2) });
  cui_text_ex(ui, "wide", &(cui_text_opts){
    .font = CUI_FONT_MEDIUM, .color = CUI_COLOR_ACCENT });
  cui_box_end(ui);
  cui_box_begin(ui, &(cui_box){ .width = CUI_PX(30), .height = CUI_PX(10),
                                .bg = CUI_COLOR_BORDER });
  cui_box_end(ui);
  cui_box_end(ui);
  cui_button_ex(ui, "Declared", &(cui_button_opts){
    .variant = CUI_BUTTON_DANGER });
  cui_text_ex(ui, "plain", &(cui_text_opts){ 0 });
  cui_box_end(ui);
}

static void method_forms_draw_what_the_c_calls_draw(void) {
  EXPECT_TRUE(same_pixels(short_forms, c_forms));
  // The comparison tells different screens apart.
  EXPECT_FALSE(same_pixels(short_forms, a_map_of_columns));
}

static void a_map_of_columns(Ui ui) {
  static cui_table_sort sort = { .column = 1 };
  ui.table ("people", sort: &sort,
            columns: {"Name": fill, "Role": unsorted(80),
                      "Score": right(grow(0.5)), "Seen": center(70)})
  ui.each (String name in %("Ada" "Grace")) ui.table_row (row) {
    ui.cell_text(name);
    ui.cell () ui.badge("Admin", tone: info);
    ui.cell_text("12");
    ui.cell_text("Mon");
  }
}

static void an_array_of_columns(Ui ui) {
  static cui_table_sort sort = { .column = 1 };
  cui_table_column columns[] = {
    { "Name", CUI_FILL, CUI_TEXT_LEFT, true },
    { "Role", CUI_PX(80), CUI_TEXT_LEFT, false },
    { "Score", CUI_GROW(0.5), CUI_TEXT_RIGHT, true },
    { "Seen", CUI_PX(70), CUI_TEXT_CENTER, true },
  };
  if (!cui_table_begin_ex(ui, "people", columns, 4,
                          &(cui_table_opts){ .sort = &sort }))
    return;
  foreach (String name in %("Ada" "Grace")) {
    cui_push_id_int(ui, name == "Ada" ? 0 : 1);
    cui_table_row(ui, false);
    cui_table_cell_text(ui, name);
    cui_table_cell(ui);
    cui_badge_ex(ui, "Admin", &(cui_badge_opts){ .tone = CUI_TONE_INFO });
    cui_table_cell_text(ui, "12");
    cui_table_cell_text(ui, "Mon");
    cui_pop_id(ui);
  }
  cui_table_end(ui);
}

static void a_table_takes_its_columns_from_a_map(void) {
  EXPECT_TRUE(same_pixels(a_map_of_columns, an_array_of_columns));
}

static void a_grid_with_a_map_of_columns(Ui ui) {
  static cui_table_sort sort = { .column = 0 };
  ui.data_grid ("grid", 30, first, last,
                columns: {"Name": 120, "Done": unsorted(60),
                          "Score": right(80)},
                height: 200, sort: &sort)
    for (int row = first; row < last; row++) {
      ui.data_grid_row(row);
      ui.grid_cell_text(%"name $row");
      ui.grid_cell_text(row % 2 ? "yes" : "no");
      ui.grid_cell_text(%"$(row * 3)");
    }
}

static void a_grid_with_an_array_of_columns(Ui ui) {
  static cui_table_sort sort = { .column = 0 };
  static cui_grid_column columns[] = {
    { "Name", 120, CUI_TEXT_LEFT, true },
    { "Done", 60, CUI_TEXT_LEFT, false },
    { "Score", 80, CUI_TEXT_RIGHT, true },
  };
  int first = 0, last = 0;
  if (!cui_data_grid_begin_ex(ui, "grid", columns, 3, 30, &first, &last,
                              &(cui_grid_opts){ .height = CUI_PX(200),
                                                .sort = &sort }))
    return;
  for (int row = first; row < last; row++) {
    cui_data_grid_row(ui, row);
    cui_data_grid_cell_text(ui, %"name $row");
    cui_data_grid_cell_text(ui, row % 2 ? "yes" : "no");
    cui_data_grid_cell_text(ui, %"$(row * 3)");
  }
  cui_data_grid_end(ui);
}

/* The data grid's method form draws what CUI's C calls draw with the same
   columns as a C array. */
static void a_data_grid_takes_its_columns_from_a_map(void) {
  EXPECT_TRUE(same_pixels(a_grid_with_a_map_of_columns,
                          a_grid_with_an_array_of_columns));
}

// id scopes and arrays

/* Components under different keys have different ids, and the same key
   gives the same id in the next frame; a text key and an integer key
   both work. */
static void an_id_scope_keeps_state_per_key(void) {
  Offscreen screen = auto Offscreen.open(200, 120);
  cui_id ids[2][3];
  for (int pass = 0; pass < 2; pass++) {
    screen.begin();
    Ui ui = screen.ui();
    for (int k = 0; k < 2; k++) ui.id (k) {
      ui.button("Same");
      ids[pass][k] = ui.last_id();
    }
    ui.id ("named") {
      ui.button("Same");
      ids[pass][2] = ui.last_id();
    }
    screen.end();
  }
  EXPECT_TRUE(ids[0][0] != ids[0][1]);
  EXPECT_TRUE(ids[0][2] != ids[0][0] && ids[0][2] != ids[0][1]);
  for (int k = 0; k < 3; k++) EXPECT_TRUE(ids[0][k] == ids[1][k]);
}

static const cui_tab_bar_item tab_items[] = {
  { CUI_ICON_HOUSE, "Home" }, { CUI_ICON_SEARCH, "Search" },
  { CUI_ICON_USER, "Profile" } };

static void tabs_by_form(Ui ui) {
  static int selected = 0;
  ui.tab_bar("tabs", tab_items, selected);
}

static void tabs_in_c(Ui ui) {
  static int selected = 0;
  cui_tab_bar_ex(ui, "tabs", tab_items, 3, &selected, NULL);
}

static void two_tabs_by_form(Ui ui) {
  static int selected = 0;
  ui.tab_bar("tabs", tab_items, 2, selected);
}

/* An array form passes the count of its C array; a count written out is
   passed as it is. */
static void an_array_form_passes_the_count(void) {
  EXPECT_TRUE(same_pixels(tabs_by_form, tabs_in_c));
  EXPECT_FALSE(same_pixels(tabs_by_form, two_tabs_by_form));
}

// lists

typedef struct Picks {
  int clicked, passes;
  bool hovered;
  cui_rect second;       // the second row's label
} Picks;

static void draw_list(Ui ui, Picks &p) {
  ui.column (width: fill, pad: 8) {
    ui.each (String name in %("one" "two" "skipped" "three"), key: name) {
      p.passes++;
      if (name == "skipped") continue;
      ui.item (row, selected: name == "three") {
        if (row.clicked) p.clicked = name == "two" ? 2 : 1;
        if (name == "two") p.hovered = row.hovered;
        ui.label(name);
        if (name == "two") p.second = ui.last_rect();
      }
    }
  }
}

static void list_frame(Offscreen screen, Picks &p) {
  screen.begin();
  draw_list(screen.ui(), p);
  screen.end();
}

static void an_item_reports_what_the_pointer_did(void) {
  Picks p = {};
  Offscreen screen = auto Offscreen.open(240, 240);
  list_frame(screen, p);
  list_frame(screen, p);
  EXPECT_INT_EQ(p.passes, 8);
  EXPECT_INT_EQ(p.clicked, 0);
  Ui ui = screen.ui();
  ui.input_mouse_move(p.second.x + p.second.w / 2, p.second.y + 4);
  list_frame(screen, p);
  list_frame(screen, p);
  EXPECT_TRUE(p.hovered);
  ui.input_mouse_button(left, true);
  list_frame(screen, p);
  ui.input_mouse_button(left, false);
  list_frame(screen, p);
  EXPECT_INT_EQ(p.clicked, 2);
}

/* A form takes any count of ordinary arguments: the virtual list's six,
   with `fill` lowered for its `cui_size` height. */
static void a_virtual_list_draws_the_rows_in_view(void) {
  Offscreen screen = auto Offscreen.open(200, 120);
  int first = 0, last = 0;
  for (int pass = 0; pass < 3; pass++) {
    screen.begin();
    Ui ui = screen.ui();
    ui.virtual_list ("rows", 1000, 24, fill, first, last)
      for (int i = first; i < last; i++) ui.text(%"row $i");
    screen.end();
  }
  EXPECT_INT_EQ(first, 0);
  EXPECT_TRUE(last > 0 && last < 1000);
}

// What the pointer did to each of three table rows in the last frame.
typedef struct TableRows {
  RowState rows[3];
  bool disabled;
} TableRows;

static void draw_table(Ui ui, TableRows &t) {
  ui.disabled (t.disabled)
  ui.table ("rows", selectable: true, columns: {"Name": fill})
  ui.each (String name in %("one" "two" "three"))
  ui.table_row (row) {
    int i = name == "one" ? 0 : name == "two" ? 1 : 2;
    t.rows[i] = row;
    ui.cell_text(name);
  }
}

static void table_frame(Offscreen screen, TableRows &t) {
  screen.begin();
  draw_table(screen.ui(), t);
  screen.end();
}

static void a_table_row_reports_what_the_pointer_did(void) {
  TableRows t = {};
  Offscreen screen = auto Offscreen.open(240, 240);
  table_frame(screen, t);
  table_frame(screen, t);
  EXPECT_FALSE(t.rows[1].hovered);
  // A table row has no rectangle of its own to aim at, so the pointer
  // moves down the table until the second row reports it.
  Ui ui = screen.ui();
  for (int y = 0; y < 240 && !t.rows[1].hovered; y += 4) {
    ui.input_mouse_move(120, y);
    table_frame(screen, t);
    table_frame(screen, t);
  }
  EXPECT_TRUE(t.rows[1].hovered);
  EXPECT_FALSE(t.rows[0].hovered);
  EXPECT_FALSE(t.rows[2].hovered);
  ui.input_mouse_button(left, true);
  table_frame(screen, t);
  EXPECT_TRUE(t.rows[1].pressed);
  EXPECT_FALSE(t.rows[0].pressed);
  EXPECT_FALSE(t.rows[1].clicked);
  ui.input_mouse_button(left, false);
  table_frame(screen, t);
  EXPECT_TRUE(t.rows[1].clicked);
  EXPECT_FALSE(t.rows[2].clicked);

  // A disabled table's rows report nothing, as their highlight shows.
  t.disabled = true;
  table_frame(screen, t);
  table_frame(screen, t);
  EXPECT_FALSE(t.rows[1].hovered);
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
  $test.run(a_string_list_lasts_until_the_frame_is_painted);
  $test.run(formatted_text_takes_x2c_values);
  $test.run(method_forms_draw_what_the_c_calls_draw);
  $test.run(a_table_takes_its_columns_from_a_map);
  $test.run(a_data_grid_takes_its_columns_from_a_map);
  $test.run(an_item_reports_what_the_pointer_did);
  $test.run(an_id_scope_keeps_state_per_key);
  $test.run(an_array_form_passes_the_count);
  $test.run(string_lists_convert_once);
  $test.run(a_virtual_list_draws_the_rows_in_view);
  $test.run(a_table_row_reports_what_the_pointer_did);
}

int main(void) {
  TestHarness_begin();
  $test.suite(x2cui_suite);
  return TestHarness_finish();
}
