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

    Labels are Strings. A value that changes on nearly every frame is
    better drawn with the raw `cui_textf(ui, "%.1f s", seconds)`, which
    formats in CUI's own frame memory and creates no String.

    This unit is the `x2cui` package entry: `import "x2cui"` reaches every
    nonstatic name as `x2cui__*` and every `$cui.` macro. The vendored
    `cui-1.3.h` stays public because these methods take CUI's own types,
    and it is the raw API for everything below.
 */

#include "cui-1.3.h"
#include "cleanup.x"

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

/** Returns the field's writable text for a component that edits it. */
char *x2cui_buffer(TextField field) => field.buffer;

/** Copies the Strings of `items` into `names`, which holds `items.len()`
    pointers, for a component that takes `const char *const *`.
*/
void x2cui_strings(List items, const char **names) {
  int index = 0;
  foreach (String item in items) names[index++] = item;
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
$cui.method(cui_tree_begin);
$cui.method(cui_tree_end);
$cui.method(cui_tree_clicked);
$cui.method(cui_list_item_ex);
$cui.method(cui_virtual_list_begin);
$cui.method(cui_virtual_list_end);
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
$cui.method(cui_toggle_group_ex);
$cui.method(cui_confirm_button_ex);
$cui.method(cui_status_button_ex);
$cui.method(cui_theme_switcher);
$cui.method(cui_theme_toggle);
$cui.method(cui_user_menu_begin);
$cui.method(cui_user_menu_end);
$cui.method(cui_swipe_item_end);
$cui.method(cui_data_grid_row);
$cui.method(cui_data_grid_cell_text);
$cui.method(cui_data_grid_end);
$cui.method(cui_data_grid_cell);
$cui.method(cui_data_grid_cell_edit);
$cui.method(cui_data_grid_edit);
$cui.method(cui_tree_cell);
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
$cui.method(cui_multi_select_ex);
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
