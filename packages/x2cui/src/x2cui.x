/*  x2cui.x -- CUI's immediate-mode components with ordinary x2c calls.

    CUI draws its own components. A program describes the screen with calls
    on every frame; CUI lays it out, handles the mouse and keyboard, and
    draws it in a window or into pixels. This package keeps CUI's C
    implementation and its names for records, enums, and constants, and
    replaces the C calling conventions:

      ui.button("Add", { .variant = CUI_BUTTON_PRIMARY })
      ui.checkbox(task.title, task.done, {})
      $cui.row(ui, { .gap = 8 }) { ... }

    `Ui` is CUI's `cui_ctx *` and `App` is its `cui_app *`, so every raw
    CUI call takes them as they are. `Offscreen` draws with the software
    renderer into pixels, with no window. `TextField` holds text that a
    component edits in place.

    Labels are Strings. A CUI function that takes a `printf` format is a
    method that takes the format and x2c values: `ui.textf("%d items", n)`.

    This unit is the `x2cui` package entry: `import "x2cui"` reaches every
    nonstatic name as `x2cui__*` and every `$cui.` macro. The vendored
    `cui-1.3.h` stays public because these methods take CUI's own types,
    and it is the raw API for everything below.
 */

#include "cui-1.3.h"
#include "cleanup.x"
#include "typed-array.x"

/** Names CUI's `cui_ctx *` as the receiver of every component method. */
typedef cui_ctx *Ui;

/** Names CUI's `cui_app *`: one window, its event loop, and its `Ui`. */
typedef cui_app *App;

/** Draws frames into pixels with the software renderer, with no window. */
typedef struct Offscreen *Offscreen;

/** Holds text that a component edits in place, up to a fixed capacity. */
typedef struct TextField {
  char *buffer;
  size_t capacity;
} *TextField;

// The generator names Ui and TextField in the methods it builds.
#include "x2cui-generate.x"
#include "x2cui-containers.x"
#include "x2cui-arrays.x"

/** Closes the window; idempotent on NULL, and returns NULL. */
App App.close(App app);

/** Releases the renderer, the `Ui`, and the pixels; returns NULL. */
Offscreen Offscreen.close(Offscreen screen);

$cleanup.by(App, close);
$cleanup.by(Offscreen, close);

#include <stdlib.h>
#include <string.h>

// windows

/** Opens a window. Raises `<init-fail>` when CUI cannot create it. */
App App.open(cui_app_desc desc) {
  App app = cui_app_create(&desc);
  if (!app) {
    raise %(init-fail (library "cui") (operation "cui_app_create")
            (reason "CUI did not create a window"));
  }
  return app;
}

/** Presents the last frame, waits for input or animation, and begins the
    next frame. Returns false once the window has closed.
*/
inline bool App.frame(App app) => cui_app_frame(app);

/** Returns the window's borrowed `Ui`, valid until the window closes. */
inline Ui App.ui(App app) => cui_app_ui(app);

App App.close(App app) {
  if (app) cui_app_destroy(app);
  return NULL;
}

// off-screen frames

static struct Offscreen {
  cui_sw_renderer *renderer;
  Ui ui;
  unsigned char *pixels;
  int width;
  int height;
  int commands;
};

/** Opens an off-screen surface of `width` by `height` points. */
Offscreen Offscreen.open(int width, int height) {
  Offscreen screen = calloc(1, sizeof *screen);
  screen.renderer = cui_sw_create();
  screen.ui = cui_create(
    &(cui_ctx_desc){ .renderer = cui_sw_iface(screen.renderer) });
  if (!screen.renderer || !screen.ui) {
    screen.close();
    raise %(init-fail (library "cui") (operation "cui_create")
            (reason "CUI did not create a software renderer"));
  }
  cui_set_viewport(screen.ui, width, height, 1);
  return screen;
}

/** Returns the surface's borrowed `Ui`, valid until the surface closes. */
Ui Offscreen.ui(Offscreen screen) => screen.ui;

/** Begins a frame one sixtieth of a second after the last. */
void Offscreen.begin(Offscreen screen) {
  cui_begin_frame(screen.ui, 1.0f / 60);
}

/** Ends the frame and renders it into the surface's pixels. */
void Offscreen.end(Offscreen screen) {
  cui_end_frame(screen.ui);
  const cui_draw_data *data = cui_get_draw_data(screen.ui);
  if (data.width_px != screen.width || data.height_px != screen.height) {
    screen.width = data.width_px;
    screen.height = data.height_px;
    screen.pixels =
      realloc(screen.pixels, (size_t) screen.width * screen.height * 4);
  }
  screen.commands = data.command_count;
  cui_sw_render(
    screen.renderer, data, screen.pixels, screen.width, screen.height,
    screen.width * 4, CUI_SW_RGBA);
}

/** Returns how many draw commands the last frame produced. */
int Offscreen.commands(Offscreen screen) => screen.commands;

/** Writes the last frame as a PNG. Raises `<io-fail>` when it cannot. */
void Offscreen.write_png(Offscreen screen, String path) {
  if (screen.pixels &&
      cui_write_png(path, screen.pixels, screen.width, screen.height,
                    screen.width * 4))
    return;
  raise %(io-fail (library "cui") (operation "cui_write_png")
          (path $path));
}

Offscreen Offscreen.close(Offscreen screen) {
  if (!screen) return NULL;
  if (screen.ui) cui_destroy(screen.ui);
  if (screen.renderer) cui_sw_destroy(screen.renderer);
  free(screen.pixels);
  free(screen);
  return NULL;
}

// text fields

/** Returns an empty field that holds up to `capacity - 1` bytes of text. */
TextField TextField.new(int capacity) {
  TextField field = xmalloc(sizeof *field);
  field.buffer = xcalloc(1, capacity);
  field.capacity = capacity;
  return field;
}

/** Returns the field's current text. */
String TextField.text(TextField field) => String.new(field.buffer);

/** Tests whether the field holds no text. */
bool TextField.empty(TextField field) => !field.buffer[0];

/** Replaces the field's text with `text`, cut to the field's capacity. */
void TextField.set(TextField field, String text) {
  strncpy(field.buffer, text, field.capacity - 1);
  field.buffer[field.capacity - 1] = 0;
}

/** Returns the field's text and leaves the field empty. */
String TextField.take(TextField field) {
  String text = field.text();
  field.buffer[0] = 0;
  return text;
}

// component methods

/** Returns a chart series named `name` over `values`. The series borrows
    the values, which a chart copies when it is drawn.
*/
cui_series cui_series.of(String name, ArrayFloat values) =>
  (cui_series){ .name = name, .values = (const float *) values.bytes,
                .count = (int) values.len() };

/** Draws text formatted from `format` and `values` by `String.format`.
    CUI's `cui_textf` takes C variadic arguments; this takes x2c values.
*/
void Ui.textf(Ui ui, String format, List @values) =>
  cui_textf(ui, "%s", format.format(@values));

/// Draws a table cell's text formatted as `Ui.textf` formats it.
void Ui.table_cell_textf(Ui ui, String format, List @values) =>
  cui_table_cell_textf(ui, "%s", format.format(@values));

/// Writes text formatted as `Ui.textf` formats it to a terminal's buffer.
void cui_terminal_buffer.printf(cui_terminal_buffer &terminal, String format,
                                List @values) =>
  cui_terminal_printf(&terminal, "%s", format.format(@values));

/// Appends a line formatted as `Ui.textf` formats it to a log's buffer.
void cui_log_buffer.append(cui_log_buffer &log, cui_log_level level,
                           String format, List @values) =>
  cui_log_append(&log, level, "%s", format.format(@values));

/// Edits the two numbers at `value` in an inspector row.
bool Ui.prop_vec2(Ui ui, String label, float *value, cui_prop_opts opts) =>
  cui_prop_vec_ex(ui, label, value, 2, &opts);

/// Edits the three numbers at `value` in an inspector row.
bool Ui.prop_vec3(Ui ui, String label, float *value, cui_prop_opts opts) =>
  cui_prop_vec_ex(ui, label, value, 3, &opts);

/// Edits the four numbers at `value` in an inspector row.
bool Ui.prop_vec4(Ui ui, String label, float *value, cui_prop_opts opts) =>
  cui_prop_vec_ex(ui, label, value, 4, &opts);

// The x axis labels of a chart are a List in x2c and two option fields in C.
static cui_chart_opts _labelled(cui_chart_opts opts, List labels) {
  if (labels) {
    opts.labels = x2cui_strings(labels);
    opts.label_count = labels.len();
  }
  return opts;
}

/** Begins a tree node and returns true while it is open. A leaf has no
    open flag: pass NULL for `open` and set `.leaf` in `opts`.
*/
bool Ui.tree_begin(Ui ui, String label, bool &?open, cui_tree_opts opts) =>
  open ? cui_tree_begin(ui, label, &open, &opts)
       : cui_tree_begin(ui, label, NULL, &opts);

/** Draws a table cell that holds a tree node, `depth` levels in. Returns
    true when the node is clicked. A leaf has no open flag: pass NULL for
    `open`.
*/
bool Ui.tree_cell(
  Ui ui, String label, int depth, bool has_children, bool &?open,
  String icon) =>
  open ? cui_tree_cell(ui, label, depth, has_children, &open, icon)
       : cui_tree_cell(ui, label, depth, has_children, NULL, icon);

/** Draws a donut chart with one slice for each of `values`, named by the
    matching String of `labels`.
*/
void Ui.donut_chart(
  Ui ui, String id, ArrayFloat values, List labels, cui_chart_opts opts) {
  cui_donut_chart_ex(ui, id, (const float *) values.bytes,
                     x2cui_strings(labels), (int) values.len(), &opts);
}

/** Draws `values` as a small line with no axes. */
void Ui.sparkline(
  Ui ui, ArrayFloat values, cui_size width, float height, cui_color color) {
  cui_sparkline(ui, (const float *) values.bytes, (int) values.len(), width,
                height, color);
}

/** Draws `length` one-character boxes that edit `code`, a field of at
    least `length + 1` bytes. Returns true when the code changes.
*/
bool Ui.otp_input(Ui ui, String id, TextField code, int length) =>
  cui_otp_input(ui, id, code.buffer, length);

/** Begins a list whose items the user drags into a new order. `order`
    holds the item indices in display order, and CUI rewrites it.
*/
void Ui.reorder_begin(Ui ui, String id, ArrayInt order) {
  cui_reorder_begin(ui, id, (int *) order.bytes, (int) order.len());
}

/** Draws a line chart of `count` series, with `labels` along the x axis,
    or NULL for none. `$cui.line_chart` supplies the count of an array.
*/
void Ui.line_chart(
  Ui ui, String id, const cui_series *series, int count, List labels,
  cui_chart_opts opts) {
  opts = _labelled(opts, labels);
  cui_line_chart_ex(ui, id, series, count, &opts);
}

/** Draws a bar chart of `count` series, with `labels` along the x axis,
    or NULL for none. `$cui.bar_chart` supplies the count of an array.
*/
void Ui.bar_chart(
  Ui ui, String id, const cui_series *series, int count, List labels,
  cui_chart_opts opts) {
  opts = _labelled(opts, labels);
  cui_bar_chart_ex(ui, id, series, count, &opts);
}

/** Returns the field's writable text for a component that edits it. */
char *x2cui_buffer(TextField field) => field.buffer;

/* One native array for each List of Strings a component has been given.
   A List is canonical, so equal Lists are one List and one entry. The
   table is keyed by the List's address and is open-addressed. A Map would
   box each address it looks up, which allocates on every call. */
typedef struct StringArray {
  List items;
  const char **names;
} StringArray;

static StringArray *string_arrays;
static size_t string_array_slots, string_array_count;

// Returns the slot that holds `items`, or the empty slot where it belongs.
static StringArray *_string_slot(
  StringArray *table, size_t slots, List items) {
  size_t at = ((uintptr_t) items >> 4) * 0x9E3779B97F4A7C15ull;
  for (at &= slots - 1; table[at].items && table[at].items != items;)
    at = (at + 1) & (slots - 1);
  return &table[at];
}

// Keeps the table at most half full, so a probe always ends.
static void _reserve_string_slot(void) {
  if (2 * (string_array_count + 1) <= string_array_slots) return;
  size_t slots = string_array_slots ? 2 * string_array_slots : 64;
  StringArray *table = calloc(slots, sizeof *table);
  for (size_t i = 0; i < string_array_slots; i++)
    if (string_arrays[i].items)
      *_string_slot(table, slots, string_arrays[i].items) = string_arrays[i];
  free(string_arrays);
  string_arrays = table;
  string_array_slots = slots;
}

/** Returns the Strings of `items` as the array a component reads. CUI may
    read the array until the frame ends, so the array is kept and is built
    once for each distinct List.
*/
const char *const *x2cui_strings(List items) {
  _reserve_string_slot();
  StringArray *slot = _string_slot(string_arrays, string_array_slots, items);
  if (slot.items) return slot.names;
  const char **names = malloc((items.len() + 1) * sizeof *names);
  int index = 0;
  foreach (String item in items) names[index++] = item;
  *slot = (StringArray){ items, names };
  string_array_count++;
  return names;
}

$cui.method(cui_heading);
$cui.method(cui_destroy);
$cui.method(cui_set_renderer);
$cui.method(cui_set_viewport);
$cui.method(cui_viewport_size);
$cui.method(cui_dpi_scale);
$cui.method(cui_begin_frame);
$cui.method(cui_end_frame);
$cui.method(cui_needs_redraw);
$cui.method(cui_next_wakeup);
$cui.method(cui_request_redraw);
$cui.method(cui_request_wakeup);
$cui.method(cui_time);
$cui.method(cui_delta_time);
$cui.method(cui_frame_count);
$cui.method(cui_input_mouse_move);
$cui.method(cui_input_mouse_button);
$cui.method(cui_input_mouse_leave);
$cui.method(cui_input_scroll);
$cui.method(cui_input_key);
$cui.method(cui_input_text);
$cui.method(cui_input_focus);
$cui.method(cui_input_file_hover);
$cui.method(cui_input_file_drop);
$cui.method(cui_dropped_file_count);
$cui.method(cui_dropped_file);
$cui.method(cui_file_drag_active);
$cui.method(cui_set_platform);
$cui.method(cui_get_cursor);
$cui.method(cui_key_pressed);
$cui.method(cui_key_down);
$cui.method(cui_shortcut);
$cui.method(cui_key_mods);
$cui.method(cui_mouse_pos);
$cui.method(cui_mouse_down);
$cui.method(cui_mouse_clicked);
$cui.method(cui_wants_keyboard);
$cui.method(cui_wants_mouse);
$cui.method(cui_set_theme);
$cui.method(cui_get_theme_mode);
$cui.method(cui_set_accent);
$cui.method(cui_get_accent);
$cui.method(cui_theme_get);
$cui.method(cui_set_reduced_motion);
$cui.method(cui_color_of);
$cui.method(cui_set_strings);
/* The generator cannot see the `const` of a pointer result. */
inline const cui_strings *Ui.get_strings(Ui ui) => cui_get_strings(ui);
$cui.method(cui_token_color);
$cui.method(cui_font_load_memory);
$cui.method(cui_font_load_file);
$cui.method(cui_font_set_role);
$cui.method(cui_font_add_fallback);
$cui.method(cui_measure_text);
$cui.method(cui_box_begin);
$cui.method(cui_box_end);
$cui.method(cui_row_begin);
$cui.method(cui_column_begin);
$cui.method(cui_spacer);
$cui.method(cui_gap);
$cui.method(cui_separator);
$cui.method(cui_card_begin);
$cui.method(cui_card_end);
$cui.method(cui_scroll_begin);
$cui.method(cui_scroll_end);
$cui.method(cui_scroll_to);
$cui.method(cui_split_begin);
$cui.method(cui_split_next);
$cui.method(cui_split_end);
$cui.method(cui_make_id);
$cui.method(cui_push_id);
$cui.method(cui_push_id_int);
$cui.method(cui_pop_id);
$cui.method(cui_last_id);
$cui.method(cui_last_rect);
$cui.method(cui_get_rect);
$cui.method(cui_last_hovered);
$cui.method(cui_is_disabled);
$cui.method(cui_push_disabled);
$cui.method(cui_pop_disabled);
$cui.method(cui_text_ex);
$cui.method(cui_label);
$cui.method(cui_secondary);
$cui.method(cui_muted);
$cui.method(cui_code);
$cui.method(cui_kbd);
$cui.method(cui_link);
$cui.method(cui_icon);
$cui.method(cui_button_ex);
$cui.method(cui_icon_button_ex);
$cui.method(cui_segmented_ex);
$cui.method(cui_checkbox_ex);
$cui.method(cui_switch_ex);
$cui.method(cui_radio_ex);
$cui.method(cui_radio_group);
$cui.method(cui_slider_ex);
$cui.method(cui_range_slider);
$cui.method(cui_rating);
$cui.method(cui_chip_ex);
$cui.method(cui_input_ex);
$cui.method(cui_textarea_ex);
$cui.method(cui_search_ex);
$cui.method(cui_number_ex);
$cui.method(cui_select_ex);
$cui.method(cui_calendar);
$cui.method(cui_date_picker_ex);
$cui.method(cui_color_picker);
$cui.method(cui_tabs_ex);
$cui.method(cui_nav_item_ex);
$cui.method(cui_nav_section);
$cui.method(cui_breadcrumb);
$cui.method(cui_pagination);
$cui.method(cui_stepper);
$cui.method(cui_popover_begin);
$cui.method(cui_popover_end);
$cui.method(cui_popover_open);
$cui.method(cui_popover_close);
$cui.method(cui_popover_toggle);
$cui.method(cui_popover_is_open);
$cui.method(cui_menu_begin);
$cui.method(cui_menu_end);
$cui.method(cui_context_menu_begin);
$cui.method(cui_context_menu_end);
$cui.method(cui_menu_item_ex);
$cui.method(cui_menu_separator);
$cui.method(cui_menu_label);
$cui.method(cui_tooltip);
$cui.method(cui_dialog_begin);
$cui.method(cui_dialog_end);
$cui.method(cui_dialog_footer_begin);
$cui.method(cui_dialog_footer_end);
$cui.method(cui_sheet_begin);
$cui.method(cui_sheet_end);
$cui.method(cui_toast_action_clicked);
$cui.method(cui_toast_ex);
$cui.method(cui_toast_dismiss);
$cui.method(cui_alert_ex);
$cui.method(cui_progress_ex);
$cui.method(cui_spinner);
$cui.method(cui_skeleton);
$cui.method(cui_badge_ex);
$cui.method(cui_avatar_ex);
$cui.method(cui_avatar_group);
$cui.method(cui_empty_state_ex);
$cui.method(cui_metric_ex);
$cui.method(cui_meter);
$cui.method(cui_accordion_begin);
$cui.method(cui_accordion_end);
$cui.method(cui_tree_end);
$cui.method(cui_tree_clicked);
$cui.method(cui_list_item_ex);
$cui.method(cui_virtual_list_begin);
$cui.method(cui_virtual_list_end);
$cui.method(cui_table_begin_ex);
$cui.method(cui_table_row);
$cui.method(cui_table_cell);
$cui.method(cui_table_cell_text);
$cui.method(cui_table_end);
$cui.method(cui_gauge);
$cui.method(cui_image_create);
$cui.method(cui_image_load);
$cui.method(cui_image_destroy);
$cui.method(cui_image_ex);
$cui.method(cui_image_viewer_ex);
$cui.method(cui_cropper_ex);
$cui.method(cui_command_palette);
$cui.method(cui_radio_cards_ex);
$cui.method(cui_tag_input_ex);
$cui.method(cui_button_group_begin);
$cui.method(cui_button_group_end);
$cui.method(cui_copy_button);
$cui.method(cui_hold_button_ex);
$cui.method(cui_password_strength);
$cui.method(cui_timeline_item_ex);
$cui.method(cui_reorder_end);
$cui.method(cui_reorder_item_begin);
$cui.method(cui_reorder_item_end);
$cui.method(cui_progress_ring);
$cui.method(cui_split_button_ex);
$cui.method(cui_confirm_button_ex);
$cui.method(cui_status_button_ex);
$cui.method(cui_theme_switcher);
$cui.method(cui_theme_toggle);
$cui.method(cui_user_menu_begin);
$cui.method(cui_user_menu_end);
$cui.method(cui_swipe_item_end);
$cui.method(cui_data_grid_begin_ex);
$cui.method(cui_data_grid_row);
$cui.method(cui_data_grid_cell_text);
$cui.method(cui_data_grid_end);
$cui.method(cui_data_grid_cell);
$cui.method(cui_data_grid_cell_edit);
$cui.method(cui_data_grid_edit);
$cui.method(cui_tree_table_row);
$cui.method(cui_tree_table_name);
$cui.method(cui_tree_table_end);
$cui.method(cui_tree_table_depth);
$cui.method(cui_path_bar_ex);
$cui.method(cui_path_bar_menu_begin);
$cui.method(cui_path_bar_menu_end);
$cui.method(cui_file_browser_ex);
$cui.method(cui_file_picker_ex);
$cui.method(cui_terminal_ex);
$cui.method(cui_code_block_ex);
$cui.method(cui_json_view_ex);
$cui.method(cui_markdown_ex);
$cui.method(cui_code_editor_ex);
$cui.method(cui_code_editor_goto);
$cui.method(cui_code_editor_select);
$cui.method(cui_code_editor_find);
$cui.method(cui_diff_view_ex);
$cui.method(cui_chat_message_ex);
$cui.method(cui_chat_divider);
$cui.method(cui_typing_indicator);
$cui.method(cui_comment_ex);
$cui.method(cui_carousel_begin);
$cui.method(cui_carousel_slide_begin);
$cui.method(cui_carousel_slide_end);
$cui.method(cui_carousel_end);
$cui.method(cui_image_compare_ex);
$cui.method(cui_card_stack_begin);
$cui.method(cui_card_stack_item_begin);
$cui.method(cui_card_stack_item_end);
$cui.method(cui_card_stack_end);
$cui.method(cui_counter_ex);
$cui.method(cui_radial_gauge_ex);
$cui.method(cui_shimmer_text_ex);
$cui.method(cui_typewriter_ex);
$cui.method(cui_text_reveal_ex);
$cui.method(cui_word_rotate_ex);
$cui.method(cui_number_roll_ex);
$cui.method(cui_gradient_text_ex);
$cui.method(cui_spotlight_begin);
$cui.method(cui_spotlight_end);
$cui.method(cui_loader_ex);
$cui.method(cui_dock_begin);
$cui.method(cui_dock_item_ex);
$cui.method(cui_dock_separator);
$cui.method(cui_dock_end);
$cui.method(cui_control_tile_ex);
$cui.method(cui_now_playing_ex);
$cui.method(cui_reasoning_begin);
$cui.method(cui_reasoning_end);
$cui.method(cui_tool_call_ex);
$cui.method(cui_agent_status_ex);
$cui.method(cui_citation);
$cui.method(cui_context_meter_ex);
$cui.method(cui_response_actions_ex);
$cui.method(cui_chat_composer_ex);
$cui.method(cui_voice_orb_ex);
$cui.method(cui_kanban_begin);
$cui.method(cui_kanban_card_begin);
$cui.method(cui_kanban_card_end);
$cui.method(cui_kanban_column_end);
$cui.method(cui_kanban_end);
$cui.method(cui_kanban_column_begin_ex);
$cui.method(cui_hover_card_begin);
$cui.method(cui_hover_card_end);
$cui.method(cui_confirm_popover_ex);
$cui.method(cui_expandable_text_ex);
$cui.method(cui_expandable_card_begin);
$cui.method(cui_expandable_card_end);
$cui.method(cui_toc_anchor);
$cui.method(cui_banner_ex);
$cui.method(cui_countdown_ex);
$cui.method(cui_range_calendar);
$cui.method(cui_date_range_picker_ex);
$cui.method(cui_time_picker_ex);
$cui.method(cui_wheel_picker_ex);
$cui.method(cui_time_dial);
$cui.method(cui_ruler_slider_ex);
$cui.method(cui_knob_ex);
$cui.method(cui_fader_ex);
$cui.method(cui_signature_pad_ex);
$cui.method(cui_signature_clear);
$cui.method(cui_dropzone_ex);
$cui.method(cui_avatar_upload);
$cui.method(cui_inline_edit_ex);
$cui.method(cui_scrub_ex);
$cui.method(cui_money_input_ex);
$cui.method(cui_shortcut_recorder_ex);
$cui.method(cui_shortcut_label);
$cui.method(cui_node_end);
$cui.method(cui_node_link);
$cui.method(cui_node_link_created);
$cui.method(cui_node_link_removed);
$cui.method(cui_node_deleted);
$cui.method(cui_node_editor_end);
$cui.method(cui_node_editor_begin_ex);
$cui.method(cui_node_begin_ex);
$cui.method(cui_node_input_ex);
$cui.method(cui_node_output_ex);
$cui.method(cui_node_content_begin);
$cui.method(cui_node_content_end);
$cui.method(cui_menu_bar_begin);
$cui.method(cui_menu_bar_end);
$cui.method(cui_menu_bar_menu_begin);
$cui.method(cui_menu_bar_menu_end);
$cui.method(cui_toolbar_begin);
$cui.method(cui_toolbar_end);
$cui.method(cui_toolbar_button_ex);
$cui.method(cui_toolbar_separator);
$cui.method(cui_toolbar_spacer);
$cui.method(cui_status_bar_begin);
$cui.method(cui_status_bar_end);
$cui.method(cui_status_bar_spacer);
$cui.method(cui_status_bar_text_ex);
$cui.method(cui_status_bar_item_ex);
$cui.method(cui_status_bar_progress_ex);
$cui.method(cui_dock_panel_end);
$cui.method(cui_dockspace_end);
$cui.method(cui_dockspace_begin_ex);
$cui.method(cui_dock_panel_begin_ex);
$cui.method(cui_dock_save);
$cui.method(cui_dock_load);
$cui.method(cui_inspector_group);
$cui.method(cui_inspector_end);
$cui.method(cui_inspector_begin_ex);
$cui.method(cui_prop_float_ex);
$cui.method(cui_prop_int_ex);
$cui.method(cui_prop_text_ex);
$cui.method(cui_prop_bool_ex);
$cui.method(cui_prop_enum_ex);
$cui.method(cui_prop_color_ex);
$cui.method(cui_log_view_ex);
$cui.method(cui_emoji_font_load_file);
$cui.method(cui_emoji_font_load_memory);
$cui.method(cui_emoji_font_load_system);
$cui.method(cui_emoji_supported);
$cui.method(cui_draw_emoji);
$cui.method(cui_emoji);
$cui.method(cui_emoji_picker_ex);
$cui.method(cui_hex_view_goto);
$cui.method(cui_flame_span_rect);
$cui.method(cui_schedule_picker_ex);
$cui.method(cui_cron_describe);
$cui.method(cui_regex_tester_ex);
$cui.method(cui_request_bar_ex);
$cui.method(cui_response_status);
$cui.method(cui_draw_rect);
$cui.method(cui_draw_rect_border);
$cui.method(cui_draw_rect_gradient);
$cui.method(cui_draw_shadow);
$cui.method(cui_draw_line);
$cui.method(cui_draw_circle);
$cui.method(cui_draw_arc);
$cui.method(cui_draw_text);
$cui.method(cui_draw_icon);
$cui.method(cui_draw_image);
$cui.method(cui_push_clip);
$cui.method(cui_pop_clip);
$cui.method(cui_canvas);
$cui.method(cui_state);
$cui.method(cui_state_on_free);
$cui.method(cui_animate);
$cui.method(cui_animate_spring);
/* The generator cannot see the `const` of a pointer result. */
inline const cui_draw_data *Ui.get_draw_data(Ui ui) => cui_get_draw_data(ui);

// Components that take arrays. Rerun tools/gen-arrays.py to refresh these.

/* gen-arrays: begin generated methods */

/** Calls `cui_tour_ex`. */
inline int Ui.tour(
  Ui ui, String id, const cui_tour_step *steps, int count, int &step,
  cui_tour_opts opts) =>
  cui_tour_ex(ui, id, steps, count, &step, &opts);

/** Calls `cui_toggle_group_ex`. */
inline bool Ui.toggle_group(
  Ui ui, String id, List labels, bool *values, cui_toggle_group_opts opts) =>
  cui_toggle_group_ex(
    ui, id, x2cui_strings(labels), labels.len(), values, &opts);

/** Calls `cui_reactions`. */
inline int Ui.reactions(Ui ui, String id, cui_reaction *items, int count) =>
  cui_reactions(ui, id, items, count);

/** Calls `cui_speed_dial_ex`. */
inline int Ui.speed_dial(
  Ui ui, String id, const cui_speed_action *actions, int count,
  cui_speed_dial_opts opts) =>
  cui_speed_dial_ex(ui, id, actions, count, &opts);

/** Calls `cui_swipe_item_begin`. */
inline void Ui.swipe_item_begin(
  Ui ui, String id, const cui_swipe_action *left, int left_count,
  const cui_swipe_action *right, int right_count) =>
  cui_swipe_item_begin(ui, id, left, left_count, right, right_count);

/** Calls `cui_filter_bar`. */
inline bool Ui.filter_bar(
  Ui ui, String id, const cui_filter_field *fields, int count,
  uint32_t *selected, TextField search) =>
  cui_filter_bar(
    ui, id, fields, count, selected, x2cui_buffer(search), search.capacity);

/** Calls `cui_tree_table_begin_ex`. */
inline void Ui.tree_table_begin(
  Ui ui, String id, const cui_grid_column *columns, int column_count,
  cui_tree_node *nodes, int node_count, cui_tree_table_opts opts) =>
  cui_tree_table_begin_ex(
    ui, id, columns, column_count, nodes, node_count, &opts);

/** Calls `cui_diff_view_rows`. */
inline int Ui.diff_view_rows(
  Ui ui, String id, cui_diff_row *rows, int first, int cap) =>
  cui_diff_view_rows(ui, id, rows, first, cap);

/** Calls `cui_presence`. */
inline void Ui.presence(
  Ui ui, String id, const cui_presence_user *users, int count, int max_visible,
  float size) =>
  cui_presence(ui, id, users, count, max_visible, size);

/** Calls `cui_ticker_ex`. */
inline void Ui.ticker(
  Ui ui, String id, const cui_ticker_item *items, int count,
  cui_ticker_opts opts) =>
  cui_ticker_ex(ui, id, items, count, &opts);

/** Calls `cui_heatmap_ex`. */
inline int Ui.heatmap(
  Ui ui, String id, const float *values, int rows, int cols,
  cui_heatmap_opts opts) =>
  cui_heatmap_ex(ui, id, values, rows, cols, &opts);

/** Calls `cui_calendar_heatmap_ex`. */
inline int Ui.calendar_heatmap(
  Ui ui, String id, cui_date start, const float *values, int days,
  cui_calendar_heatmap_opts opts) =>
  cui_calendar_heatmap_ex(ui, id, start, values, days, &opts);

/** Calls `cui_treemap_ex`. */
inline int Ui.treemap(
  Ui ui, String id, const cui_viz_item *items, int count,
  cui_treemap_opts opts) =>
  cui_treemap_ex(ui, id, items, count, &opts);

/** Calls `cui_radar_chart_ex`. */
inline int Ui.radar_chart(
  Ui ui, String id, const cui_series *series, int count, List axes,
  cui_radar_opts opts) =>
  cui_radar_chart_ex(
    ui, id, series, count, x2cui_strings(axes), axes.len(), &opts);

/** Calls `cui_funnel_ex`. */
inline int Ui.funnel(
  Ui ui, String id, const cui_viz_item *stages, int count,
  cui_funnel_opts opts) =>
  cui_funnel_ex(ui, id, stages, count, &opts);

/** Calls `cui_sankey_ex`. */
inline int Ui.sankey(
  Ui ui, String id, List nodes, const cui_sankey_link *links, int link_count,
  cui_sankey_opts opts) =>
  cui_sankey_ex(
    ui, id, x2cui_strings(nodes), nodes.len(), links, link_count, &opts);

/** Calls `cui_waffle_ex`. */
inline int Ui.waffle(
  Ui ui, String id, const cui_viz_item *items, int count,
  cui_waffle_opts opts) =>
  cui_waffle_ex(ui, id, items, count, &opts);

/** Calls `cui_split_bar_ex`. */
inline int Ui.split_bar(
  Ui ui, String id, const cui_viz_item *items, int count,
  cui_split_bar_opts opts) =>
  cui_split_bar_ex(ui, id, items, count, &opts);

/** Calls `cui_bar_list_ex`. */
inline int Ui.bar_list(
  Ui ui, String id, const cui_viz_item *items, int count,
  cui_bar_list_opts opts) =>
  cui_bar_list_ex(ui, id, items, count, &opts);

/** Calls `cui_activity_rings_ex`. */
inline int Ui.activity_rings(
  Ui ui, String id, const cui_viz_item *rings, int count,
  cui_rings_opts opts) =>
  cui_activity_rings_ex(ui, id, rings, count, &opts);

/** Calls `cui_scatter_chart_ex`. */
inline int Ui.scatter_chart(
  Ui ui, String id, const cui_scatter_series *series, int count,
  cui_scatter_opts opts) =>
  cui_scatter_chart_ex(ui, id, series, count, &opts);

/** Calls `cui_candlestick_ex`. */
inline int Ui.candlestick(
  Ui ui, String id, const cui_candle *candles, int count,
  cui_candlestick_opts opts) =>
  cui_candlestick_ex(ui, id, candles, count, &opts);

/** Calls `cui_tab_bar_ex`. */
inline bool Ui.tab_bar(
  Ui ui, String id, const cui_tab_bar_item *items, int count, int &selected,
  cui_tab_bar_opts opts) =>
  cui_tab_bar_ex(ui, id, items, count, &selected, &opts);

/** Calls `cui_waveform_ex`. */
inline bool Ui.waveform(
  Ui ui, String id, const float *peaks, int count, float &progress,
  cui_waveform_opts opts) =>
  cui_waveform_ex(ui, id, peaks, count, &progress, &opts);

/** Calls `cui_agent_plan_ex`. */
inline int Ui.agent_plan(
  Ui ui, String id, const cui_plan_step *steps, int count,
  cui_agent_plan_opts opts) =>
  cui_agent_plan_ex(ui, id, steps, count, &opts);

/** Calls `cui_source_list`. */
inline int Ui.source_list(
  Ui ui, String id, const cui_source *sources, int count) =>
  cui_source_list(ui, id, sources, count);

/** Calls `cui_prompt_suggestions_ex`. */
inline int Ui.prompt_suggestions(
  Ui ui, String id, const cui_prompt_suggestion *items, int count,
  cui_prompt_suggestions_opts opts) =>
  cui_prompt_suggestions_ex(ui, id, items, count, &opts);

/** Calls `cui_model_picker_ex`. */
inline bool Ui.model_picker(
  Ui ui, String id, const cui_model *models, int count, int &selected,
  cui_model_picker_opts opts) =>
  cui_model_picker_ex(ui, id, models, count, &selected, &opts);

/** Calls `cui_week_calendar_ex`. */
inline int Ui.week_calendar(
  Ui ui, String id, cui_date week_start, cui_cal_event *events, int count,
  cui_week_opts opts) =>
  cui_week_calendar_ex(ui, id, week_start, events, count, &opts);

/** Calls `cui_month_calendar_ex`. */
inline cui_month_result Ui.month_calendar(
  Ui ui, String id, cui_date &month, const cui_month_event *events, int count,
  cui_month_opts opts) =>
  cui_month_calendar_ex(ui, id, &month, events, count, &opts);

/** Calls `cui_gantt_ex`. */
inline int Ui.gantt(
  Ui ui, String id, cui_gantt_task *tasks, int count, cui_date origin,
  int days, cui_gantt_opts opts) =>
  cui_gantt_ex(ui, id, tasks, count, origin, days, &opts);

/** Calls `cui_toc`. */
inline int Ui.toc(
  Ui ui, String scroll_id, const cui_toc_item *items, int count) =>
  cui_toc(ui, scroll_id, items, count);

/** Calls `cui_checklist_ex`. */
inline int Ui.checklist(
  Ui ui, String id, cui_check_step *steps, int count,
  cui_checklist_opts opts) =>
  cui_checklist_ex(ui, id, steps, count, &opts);

/** Calls `cui_multi_select_ex`. */
inline bool Ui.multi_select(
  Ui ui, String id, List items, bool *selected, cui_multi_select_opts opts) =>
  cui_multi_select_ex(
    ui, id, x2cui_strings(items), items.len(), selected, &opts);

/** Calls `cui_histogram_slider_ex`. */
inline bool Ui.histogram_slider(
  Ui ui, String label, const float *bins, int bin_count, float &lo, float &hi,
  float min, float max, cui_histogram_opts opts) =>
  cui_histogram_slider_ex(
    ui, label, bins, bin_count, &lo, &hi, min, max, &opts);

/** Calls `cui_level_meter_ex`. */
inline bool Ui.level_meter(
  Ui ui, String id, const float *levels, int channels,
  cui_level_meter_opts opts) =>
  cui_level_meter_ex(ui, id, levels, channels, &opts);

/** Calls `cui_doc_tabs_ex`. */
inline cui_doc_tabs_result Ui.doc_tabs(
  Ui ui, String id, const cui_doc_tab *tabs, int count, int &selected,
  cui_doc_tabs_opts opts) =>
  cui_doc_tabs_ex(ui, id, tabs, count, &selected, &opts);

/** Calls `cui_prop_vec_ex`. */
inline bool Ui.prop_vec(
  Ui ui, String label, float *value, int components, cui_prop_opts opts) =>
  cui_prop_vec_ex(ui, label, value, components, &opts);

/** Calls `cui_hex_view_ex`. */
inline cui_hex_result Ui.hex_view(
  Ui ui, String id, const uint8_t *data, size_t size, cui_hex_selection &sel,
  cui_hex_view_opts opts) =>
  cui_hex_view_ex(ui, id, data, size, &sel, &opts);

/** Calls `cui_flame_graph_ex`. */
inline cui_flame_result Ui.flame_graph(
  Ui ui, String id, const cui_flame_span *spans, int count,
  cui_flame_view &view, int &selected, cui_flame_opts opts) =>
  cui_flame_graph_ex(ui, id, spans, count, &view, &selected, &opts);

/** Calls `cui_curve_editor_ex`. */
inline cui_curve_result Ui.curve_editor(
  Ui ui, String id, cui_curve_key *keys, int &count, int capacity,
  cui_curve_opts opts) =>
  cui_curve_editor_ex(ui, id, keys, &count, capacity, &opts);

/** Calls `cui_gradient_editor_ex`. */
inline cui_gradient_result Ui.gradient_editor(
  Ui ui, String id, cui_gradient_stop *stops, int &count, int capacity,
  cui_gradient_opts opts) =>
  cui_gradient_editor_ex(ui, id, stops, &count, capacity, &opts);

/** Calls `cui_timeline_editor_ex`. */
inline cui_timeline_editor_result Ui.timeline_editor(
  Ui ui, String id, cui_timeline_track *tracks, int count, float &time,
  cui_timeline_editor_opts opts) =>
  cui_timeline_editor_ex(ui, id, tracks, count, &time, &opts);

/** Calls `cui_kv_editor_ex`. */
inline bool Ui.kv_editor(
  Ui ui, String id, cui_kv_pair *pairs, int &count, int capacity,
  cui_kv_editor_opts opts) =>
  cui_kv_editor_ex(ui, id, pairs, &count, capacity, &opts);

/** Calls `cui_problems_ex`. */
inline cui_problems_result Ui.problems(
  Ui ui, String id, const cui_diagnostic *diags, int count,
  cui_problems_opts opts) =>
  cui_problems_ex(ui, id, diags, count, &opts);

/** Calls `cui_pipeline_ex`. */
inline cui_pipeline_result Ui.pipeline(
  Ui ui, String id, List stages, const cui_pipeline_job *jobs, int job_count,
  cui_pipeline_opts opts) =>
  cui_pipeline_ex(
    ui, id, x2cui_strings(stages), stages.len(), jobs, job_count, &opts);

/** Calls `cui_query_builder_ex`. */
inline bool Ui.query_builder(
  Ui ui, String id, const cui_query_field *fields, int field_count,
  cui_query_node *nodes, int &count, int capacity, cui_query_opts opts) =>
  cui_query_builder_ex(
    ui, id, fields, field_count, nodes, &count, capacity, &opts);

/** Calls `cui_keymap_ex`. */
inline cui_keymap_result Ui.keymap(
  Ui ui, String id, const cui_keymap_binding *bindings, int count,
  cui_keymap_opts opts) =>
  cui_keymap_ex(ui, id, bindings, count, &opts);

/** Calls `cui_commit_graph_ex`. */
inline cui_commit_graph_result Ui.commit_graph(
  Ui ui, String id, const cui_commit *commits, int count,
  cui_commit_graph_opts opts) =>
  cui_commit_graph_ex(ui, id, commits, count, &opts);

/** Calls `cui_graph_view_ex`. */
inline cui_graph_result Ui.graph_view(
  Ui ui, String id, const cui_graph_node *nodes, int node_count,
  const cui_graph_edge *edges, int edge_count, cui_graph_opts opts) =>
  cui_graph_view_ex(ui, id, nodes, node_count, edges, edge_count, &opts);

/** Calls `cui_waterfall_ex`. */
inline cui_waterfall_result Ui.waterfall(
  Ui ui, String id, const cui_net_request *requests, int count,
  cui_waterfall_opts opts) =>
  cui_waterfall_ex(ui, id, requests, count, &opts);

/** Calls `cui_trace_view_ex`. */
inline cui_trace_result Ui.trace_view(
  Ui ui, String id, cui_trace_track *tracks, int track_count,
  const cui_trace_span *spans, int span_count, cui_trace_view &view,
  int &selected, cui_trace_opts opts) =>
  cui_trace_view_ex(
    ui, id, tracks, track_count, spans, span_count, &view, &selected, &opts);

/** Calls `cui_test_explorer_ex`. */
inline cui_test_explorer_result Ui.test_explorer(
  Ui ui, String id, const cui_test_item *items, int count,
  cui_test_explorer_opts opts) =>
  cui_test_explorer_ex(ui, id, items, count, &opts);

/** Calls `cui_stack_trace_ex`. */
inline cui_stack_trace_result Ui.stack_trace(
  Ui ui, String id, const cui_stack_frame *frames, int count,
  cui_stack_trace_opts opts) =>
  cui_stack_trace_ex(ui, id, frames, count, &opts);

/** Calls `cui_uptime_ex`. */
inline cui_uptime_result Ui.uptime(
  Ui ui, String id, const cui_uptime_service *services, int count,
  cui_uptime_opts opts) =>
  cui_uptime_ex(ui, id, services, count, &opts);

/** Calls `cui_time_histogram_ex`. */
inline cui_time_histogram_result Ui.time_histogram(
  Ui ui, String id, double start, double bucket_seconds, int buckets,
  const cui_histogram_series *series, int series_count, double &sel_start,
  double &sel_end, cui_time_histogram_opts opts) =>
  cui_time_histogram_ex(
    ui, id, start, bucket_seconds, buckets, series, series_count, &sel_start,
    &sel_end, &opts);

/** Calls `cui_coverage_ex`. */
inline cui_coverage_result Ui.coverage(
  Ui ui, String id, const cui_coverage_file *files, int count,
  cui_coverage_opts opts) =>
  cui_coverage_ex(ui, id, files, count, &opts);

/** Calls `cui_blame_ex`. */
inline cui_blame_result Ui.blame(
  Ui ui, String id, List lines, const int *line_commit, int line_count,
  const cui_blame_commit *commits, int commit_count, cui_blame_opts opts) =>
  cui_blame_ex(
    ui, id, x2cui_strings(lines), line_commit, line_count, commits,
    commit_count, &opts);

/** Calls `cui_feature_flags_ex`. */
inline cui_feature_flags_result Ui.feature_flags(
  Ui ui, String id, cui_feature_flag *flags, int count, List envs,
  cui_feature_flags_opts opts) =>
  cui_feature_flags_ex(
    ui, id, flags, count, x2cui_strings(envs), envs.len(), &opts);

/** Calls `cui_api_explorer_ex`. */
inline cui_api_explorer_result Ui.api_explorer(
  Ui ui, String id, const cui_api_endpoint *endpoints, int count,
  cui_api_explorer_opts opts) =>
  cui_api_explorer_ex(ui, id, endpoints, count, &opts);

/** Calls `cui_draw_polyline`. */
inline void Ui.draw_polyline(
  Ui ui, const cui_vec2 *points, int count, float thickness, cui_color color,
  bool closed) =>
  cui_draw_polyline(ui, points, count, thickness, color, closed);

/** Calls `cui_draw_polygon`. */
inline void Ui.draw_polygon(
  Ui ui, const cui_vec2 *points, int count, cui_color color) =>
  cui_draw_polygon(ui, points, count, color);

/* gen-arrays: end generated methods */
