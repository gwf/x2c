#pragma once

#include "x2c.x"
#include "meta.x"
#include "x2cui-options.x"

/*  x2cui-generate.x -- Ui methods built from CUI's C signatures

    `$x2cui.method(cui_button_ex)` defines `Ui.button` from the type of
    `cui_button_ex` as the compiler read it from `cui.h`. The method keeps
    the C function's result and replaces each C parameter convention with
    its x2c form:

      cui_ctx *                        the Ui receiver
      const char *                     String
      char *, size_t                   TextField
      const char *const *, int         List of Strings
      const RECORD *, int              unchanged: an array and its count
      const RECORD *                   RECORD by value, as `{ .field = v }`
      T *                              T &

    A `const char *` result is a String.

    Every other parameter passes unchanged. The table of rows is in
    x2cui.x. A function that takes an array of records or numbers has no
    row here, because its pointer is not one of these conventions.

    A component that takes an option record, and each of CUI's block
    components, also gets a method form; see "Method forms" below.
*/

meta static int _pointer(List type) => type.len() > 1 && type[0] == <*>;

meta static int _const_pointer(List type) =>
  type.len() > 2 && type[0] == <*> && type[1] == <const>;

meta static int _function(List type) =>
  type.len() > 0 && type[0] == <func>;

meta static int _spelled(List type, String shape) => type.repr() == shape;

/* `cui_button_ex` is `button`, and `cui_draw_rect` is `draw_rect`. */
meta static String _method_name(String function) {
  String name = function[4:];
  return name.endswith("_ex") ? name[:name.len() - 3] : name;
}

/* CUI's names for the parameters after the context of each function the
   `expand` table defines a method for, from cui.h. */
/* gen-arrays: begin generated parameter names */

meta static List _parameter_names = %(
  ("cui_destroy") ("cui_set_renderer" "renderer")
  ("cui_set_viewport" "width" "height" "scale") ("cui_viewport_size")
  ("cui_dpi_scale") ("cui_begin_frame" "dt") ("cui_end_frame")
  ("cui_needs_redraw") ("cui_next_wakeup") ("cui_request_redraw")
  ("cui_request_wakeup" "seconds") ("cui_time") ("cui_delta_time")
  ("cui_frame_count") ("cui_input_mouse_move" "x" "y")
  ("cui_input_mouse_button" "button" "down") ("cui_input_mouse_leave")
  ("cui_input_scroll" "dx" "dy") ("cui_input_key" "key" "down" "mods")
  ("cui_input_text" "utf8") ("cui_input_focus" "window_focused")
  ("cui_input_file_hover" "hovering" "x" "y")
  ("cui_input_file_drop" "paths" "count" "x" "y") ("cui_dropped_file_count")
  ("cui_dropped_file" "index") ("cui_file_drag_active")
  ("cui_set_platform" "platform") ("cui_get_cursor")
  ("cui_key_pressed" "key") ("cui_key_down" "key")
  ("cui_shortcut" "mods" "key") ("cui_key_mods") ("cui_mouse_pos")
  ("cui_mouse_down" "b") ("cui_mouse_clicked" "b") ("cui_wants_keyboard")
  ("cui_wants_mouse") ("cui_set_theme" "mode") ("cui_get_theme_mode")
  ("cui_set_accent" "accent") ("cui_get_accent") ("cui_theme_get")
  ("cui_set_reduced_motion" "reduced") ("cui_color_of" "c")
  ("cui_set_strings" "strings") ("cui_get_strings")
  ("cui_token_color" "token") ("cui_font_load_memory" "data" "size" "copy")
  ("cui_font_load_file" "path") ("cui_font_set_role" "role" "font")
  ("cui_font_add_fallback" "font" "fallback")
  ("cui_measure_text" "font" "size" "text" "len") ("cui_box_begin" "opts")
  ("cui_box_end") ("cui_row_begin" "opts") ("cui_column_begin" "opts")
  ("cui_spacer") ("cui_gap" "size") ("cui_separator")
  ("cui_card_begin" "opts") ("cui_card_end") ("cui_scroll_begin" "opts")
  ("cui_scroll_end") ("cui_scroll_to" "scroll_id" "y")
  ("cui_split_begin" "id" "ratio" "opts") ("cui_split_next")
  ("cui_split_end") ("cui_make_id" "str") ("cui_push_id" "str")
  ("cui_push_id_int" "value") ("cui_pop_id") ("cui_last_id")
  ("cui_last_rect") ("cui_get_rect" "id") ("cui_last_hovered")
  ("cui_is_disabled") ("cui_push_disabled" "disabled") ("cui_pop_disabled")
  ("cui_text_ex" "text" "opts") ("cui_heading" "text" "level")
  ("cui_label" "text") ("cui_secondary" "text") ("cui_muted" "text")
  ("cui_code" "text") ("cui_kbd" "keys") ("cui_link" "text")
  ("cui_icon" "icon" "size" "color") ("cui_button_ex" "label" "opts")
  ("cui_icon_button_ex" "icon" "opts")
  ("cui_segmented_ex" "id" "items" "count" "index" "opts")
  ("cui_checkbox_ex" "label" "value" "opts")
  ("cui_switch_ex" "label" "value" "opts")
  ("cui_radio_ex" "label" "value" "option" "opts")
  ("cui_radio_group" "id" "items" "count" "index")
  ("cui_slider_ex" "label" "value" "min" "max" "opts")
  ("cui_range_slider" "label" "lo" "hi" "min" "max")
  ("cui_rating" "id" "value" "max") ("cui_chip_ex" "label" "selected" "opts")
  ("cui_input_ex" "id" "buf" "cap" "opts")
  ("cui_textarea_ex" "id" "buf" "cap" "opts")
  ("cui_search_ex" "id" "buf" "cap" "opts")
  ("cui_number_ex" "id" "value" "min" "max" "opts")
  ("cui_select_ex" "id" "items" "count" "index" "opts")
  ("cui_calendar" "id" "value") ("cui_date_picker_ex" "id" "value" "opts")
  ("cui_color_picker" "id" "value")
  ("cui_tabs_ex" "id" "items" "count" "index" "opts")
  ("cui_nav_item_ex" "label" "opts") ("cui_nav_section" "title")
  ("cui_breadcrumb" "items" "count")
  ("cui_pagination" "id" "page" "page_count")
  ("cui_stepper" "steps" "count" "current") ("cui_popover_begin" "id" "opts")
  ("cui_popover_end") ("cui_popover_open" "id") ("cui_popover_close" "id")
  ("cui_popover_toggle" "id") ("cui_popover_is_open" "id")
  ("cui_menu_begin" "label" "opts") ("cui_menu_end")
  ("cui_context_menu_begin" "id") ("cui_context_menu_end")
  ("cui_menu_item_ex" "label" "opts") ("cui_menu_separator")
  ("cui_menu_label" "text") ("cui_tooltip" "text")
  ("cui_dialog_begin" "title" "open" "opts") ("cui_dialog_end")
  ("cui_dialog_footer_begin") ("cui_dialog_footer_end")
  ("cui_sheet_begin" "title" "open" "opts") ("cui_sheet_end")
  ("cui_toast_ex" "title" "opts") ("cui_toast_action_clicked" "handle")
  ("cui_toast_dismiss" "handle") ("cui_alert_ex" "title" "opts")
  ("cui_progress_ex" "value" "opts") ("cui_spinner" "size")
  ("cui_skeleton" "width" "height") ("cui_badge_ex" "text" "opts")
  ("cui_avatar_ex" "name" "opts")
  ("cui_avatar_group" "names" "count" "max_visible" "size")
  ("cui_empty_state_ex" "title" "opts")
  ("cui_metric_ex" "label" "value" "opts")
  ("cui_meter" "label" "used" "total" "unit")
  ("cui_accordion_begin" "title" "open") ("cui_accordion_end")
  ("cui_tree_end") ("cui_tree_clicked") ("cui_list_item_ex" "title" "opts")
  ("cui_virtual_list_begin" "id" "count" "row_height" "height" "first" "last")
  ("cui_virtual_list_end")
  ("cui_table_begin_ex" "id" "columns" "column_count" "opts")
  ("cui_table_row" "selected") ("cui_table_row_hovered")
  ("cui_table_row_pressed") ("cui_table_cell")
  ("cui_table_cell_text" "text") ("cui_table_end")
  ("cui_gauge" "label" "value" "size") ("cui_image_create" "w" "h" "rgba")
  ("cui_image_load" "path" "w" "h") ("cui_image_destroy" "tex")
  ("cui_image_ex" "tex" "opts")
  ("cui_image_viewer_ex" "id" "tex" "image_w" "image_h" "view" "opts")
  ("cui_cropper_ex" "id" "tex" "image_w" "image_h" "crop" "opts")
  ("cui_command_palette" "open" "commands" "count")
  ("cui_radio_cards_ex" "id" "choices" "count" "index" "opts")
  ("cui_tag_input_ex" "id" "buf" "cap" "opts") ("cui_button_group_begin")
  ("cui_button_group_end") ("cui_copy_button" "id" "text")
  ("cui_hold_button_ex" "label" "opts") ("cui_password_strength" "password")
  ("cui_timeline_item_ex" "title" "opts") ("cui_reorder_end")
  ("cui_reorder_item_begin" "position") ("cui_reorder_item_end")
  ("cui_progress_ring" "label" "value" "size")
  ("cui_split_button_ex" "label" "items" "count" "opts")
  ("cui_confirm_button_ex" "label" "opts")
  ("cui_status_button_ex" "label" "status" "opts")
  ("cui_theme_switcher" "mode" "with_system") ("cui_theme_toggle")
  ("cui_user_menu_begin" "name" "opts") ("cui_user_menu_end")
  ("cui_swipe_item_end")
  ("cui_data_grid_begin_ex" "id" "columns" "column_count" "row_count" "first" "last" "opts")
  ("cui_data_grid_row" "row") ("cui_data_grid_cell")
  ("cui_data_grid_cell_text" "text") ("cui_data_grid_cell_edit" "buf" "cap")
  ("cui_data_grid_edit" "buf" "cap") ("cui_data_grid_end")
  ("cui_tree_table_row") ("cui_tree_table_name" "label" "icon")
  ("cui_tree_table_depth") ("cui_tree_table_end")
  ("cui_path_bar_ex" "id" "segments" "count" "opts")
  ("cui_path_bar_menu_begin" "id" "segment") ("cui_path_bar_menu_end")
  ("cui_file_browser_ex" "id" "path" "path_cap" "opts")
  ("cui_file_picker_ex" "id" "open" "out" "out_cap" "opts")
  ("cui_code_block_ex" "id" "code" "opts")
  ("cui_json_view_ex" "id" "json" "opts")
  ("cui_markdown_ex" "id" "text" "opts")
  ("cui_code_editor_ex" "id" "buf" "cap" "opts")
  ("cui_code_editor_goto" "id" "line" "column")
  ("cui_code_editor_select" "id" "anchor" "cursor")
  ("cui_code_editor_find" "id" "query")
  ("cui_diff_view_ex" "id" "old_text" "new_text" "opts")
  ("cui_chat_message_ex" "text" "opts") ("cui_chat_divider" "label")
  ("cui_typing_indicator" "name")
  ("cui_comment_ex" "id" "author" "text" "opts")
  ("cui_carousel_begin" "id" "count" "index" "opts")
  ("cui_carousel_slide_begin") ("cui_carousel_slide_end")
  ("cui_carousel_end")
  ("cui_image_compare_ex" "id" "before" "after" "pos" "opts")
  ("cui_card_stack_begin" "id" "count" "opts")
  ("cui_card_stack_item_begin" "depth") ("cui_card_stack_item_end")
  ("cui_card_stack_end") ("cui_counter_ex" "id" "value" "opts")
  ("cui_radial_gauge_ex" "id" "value" "min" "max" "opts")
  ("cui_shimmer_text_ex" "text" "opts")
  ("cui_typewriter_ex" "id" "text" "opts")
  ("cui_text_reveal_ex" "id" "text" "opts")
  ("cui_word_rotate_ex" "id" "words" "count" "interval" "opts")
  ("cui_number_roll_ex" "id" "text" "opts")
  ("cui_gradient_text_ex" "text" "opts") ("cui_spotlight_begin" "id" "opts")
  ("cui_spotlight_end") ("cui_loader_ex" "opts")
  ("cui_dock_begin" "id" "opts") ("cui_dock_item_ex" "icon" "label" "opts")
  ("cui_dock_separator") ("cui_dock_end")
  ("cui_control_tile_ex" "label" "on" "opts")
  ("cui_now_playing_ex" "id" "np" "opts") ("cui_reasoning_begin" "id" "opts")
  ("cui_reasoning_end") ("cui_tool_call_ex" "id" "name" "opts")
  ("cui_agent_status_ex" "text" "opts") ("cui_citation" "number" "source")
  ("cui_context_meter_ex" "id" "used" "limit" "opts")
  ("cui_response_actions_ex" "id" "opts")
  ("cui_chat_composer_ex" "id" "buf" "cap" "opts")
  ("cui_voice_orb_ex" "id" "state" "level" "opts") ("cui_kanban_begin" "id")
  ("cui_kanban_column_begin_ex" "title" "card_count" "opts")
  ("cui_kanban_card_begin" "card_id") ("cui_kanban_card_end")
  ("cui_kanban_column_end") ("cui_kanban_end" "move")
  ("cui_hover_card_begin" "id" "opts") ("cui_hover_card_end")
  ("cui_confirm_popover_ex" "id" "opts")
  ("cui_expandable_text_ex" "id" "text" "opts")
  ("cui_expandable_card_begin" "title" "open" "opts")
  ("cui_expandable_card_end") ("cui_toc_anchor" "anchor")
  ("cui_banner_ex" "text" "open" "opts")
  ("cui_countdown_ex" "id" "seconds_left" "opts")
  ("cui_range_calendar" "id" "range" "months")
  ("cui_date_range_picker_ex" "id" "range" "opts")
  ("cui_time_picker_ex" "id" "hour" "minute" "opts")
  ("cui_wheel_picker_ex" "id" "items" "count" "index" "opts")
  ("cui_time_dial" "id" "hour" "minute" "size")
  ("cui_ruler_slider_ex" "label" "value" "min" "max" "opts")
  ("cui_knob_ex" "id" "value" "min" "max" "opts")
  ("cui_fader_ex" "id" "value" "min" "max" "opts")
  ("cui_signature_pad_ex" "id" "opts") ("cui_signature_clear" "id")
  ("cui_dropzone_ex" "id" "opts")
  ("cui_avatar_upload" "id" "name" "image" "size")
  ("cui_inline_edit_ex" "id" "buf" "cap" "opts")
  ("cui_scrub_ex" "label" "value" "min" "max" "opts")
  ("cui_money_input_ex" "id" "value" "opts")
  ("cui_shortcut_recorder_ex" "id" "combo" "opts")
  ("cui_shortcut_label" "combo")
  ("cui_node_editor_begin_ex" "id" "view" "opts") ("cui_node_editor_end")
  ("cui_node_begin_ex" "node_id" "x" "y" "title" "opts") ("cui_node_end")
  ("cui_node_input_ex" "pin_id" "label" "opts")
  ("cui_node_output_ex" "pin_id" "label" "opts") ("cui_node_content_begin")
  ("cui_node_content_end") ("cui_node_link" "link_id" "from_pin" "to_pin")
  ("cui_node_link_created" "from_pin" "to_pin")
  ("cui_node_link_removed" "link_id") ("cui_node_deleted" "node_id")
  ("cui_menu_bar_begin" "id" "opts") ("cui_menu_bar_end")
  ("cui_menu_bar_menu_begin" "label" "opts") ("cui_menu_bar_menu_end")
  ("cui_toolbar_begin" "id" "opts") ("cui_toolbar_end")
  ("cui_toolbar_button_ex" "icon" "opts") ("cui_toolbar_separator")
  ("cui_toolbar_spacer") ("cui_status_bar_begin" "id" "opts")
  ("cui_status_bar_end") ("cui_status_bar_spacer")
  ("cui_status_bar_text_ex" "text" "opts")
  ("cui_status_bar_item_ex" "label" "opts")
  ("cui_status_bar_progress_ex" "value" "opts")
  ("cui_dockspace_begin_ex" "id" "opts") ("cui_dockspace_end")
  ("cui_dock_panel_begin_ex" "title" "open" "opts") ("cui_dock_panel_end")
  ("cui_dock_save" "id" "buf" "cap") ("cui_dock_load" "id" "text")
  ("cui_inspector_begin_ex" "id" "opts") ("cui_inspector_end")
  ("cui_inspector_group" "title" "open")
  ("cui_prop_float_ex" "label" "value" "opts")
  ("cui_prop_int_ex" "label" "value" "opts")
  ("cui_prop_text_ex" "label" "buf" "cap" "opts")
  ("cui_prop_bool_ex" "label" "value" "opts")
  ("cui_prop_enum_ex" "label" "items" "count" "index" "opts")
  ("cui_prop_color_ex" "label" "value" "opts")
  ("cui_log_view_ex" "id" "buf" "opts") ("cui_terminal_ex" "id" "t" "opts")
  ("cui_emoji_font_load_file" "path")
  ("cui_emoji_font_load_memory" "data" "size" "copy")
  ("cui_emoji_font_load_system") ("cui_emoji_supported" "utf8" "len")
  ("cui_draw_emoji" "utf8" "len" "r") ("cui_emoji" "utf8" "size")
  ("cui_emoji_picker_ex" "id" "opts") ("cui_hex_view_goto" "id" "offset")
  ("cui_flame_span_rect" "flame" "span")
  ("cui_schedule_picker_ex" "id" "cron" "cap" "opts")
  ("cui_cron_describe" "cron")
  ("cui_regex_tester_ex" "id" "pattern" "pattern_cap" "text" "text_cap" "opts")
  ("cui_request_bar_ex" "id" "method" "url" "cap" "opts")
  ("cui_response_status" "status" "seconds" "bytes")
  ("cui_draw_rect" "r" "radius" "fill")
  ("cui_draw_rect_border" "r" "radius" "fill" "border" "border_width")
  ("cui_draw_rect_gradient" "r" "radius" "top" "bottom")
  ("cui_draw_shadow" "r" "radius" "blur" "spread" "offset" "color")
  ("cui_draw_line" "a" "b" "thickness" "color")
  ("cui_draw_circle" "center" "radius" "color")
  ("cui_draw_arc" "center" "radius" "a0" "a1" "thickness" "color")
  ("cui_draw_text" "font" "size" "pos" "color" "text" "len")
  ("cui_draw_icon" "icon" "r" "size" "color")
  ("cui_draw_image" "tex" "r" "uv" "radius" "tint") ("cui_push_clip" "r")
  ("cui_pop_clip")
  ("cui_canvas" "id" "width" "height" "paint" "user" "user_size")
  ("cui_state" "id" "size") ("cui_state_on_free" "id" "p2" "p3")
  ("cui_animate" "id" "target")
  ("cui_animate_spring" "id" "target" "duration" "bounce")
  ("cui_get_draw_data"));
/* gen-arrays: end generated parameter names */

// Parameter `i` of `function`, counted from 1 after the context.
meta static String _parameter_name(String function, int i) {
  List row = _parameter_names.find(%!(List r) => r.car() == function);
  return row ? row[i] : %"p$i";
}

/** Returns the `Ui` method that forwards to the C function `target`, and
    its method form when it has one.
*/
meta List x2cui_method(String function) {
  List target = x2c_ident(function);
  Type signature = Code.type(target);
  List types = Type.parameters(signature);
  Type result = Type.return_type(signature);
  // Returned text lives in CUI's frame memory; a String outlives the frame.
  if (_spelled(result, "(* const char)")) result = $!Type{ String };
  Array params = [], args = [], pairs = [];
  int lowers = 0;
  List ui = x2c_ident("u");
  params.push($!Param{ cui_ctx *$ui });
  args.push($!( $ui ));
  int count = types.len();
  for (int i = 1; i < count; i++) {
    Type type = types[i];
    List p = x2c_ident(_parameter_name(function, i));
    Type next = i + 1 < count ? types[i + 1] : NULL;
    lowers |= _lowers(type);
    if (_spelled(type, "(* const char)")) {
      params.push($!Param{ String $p });
      args.push($!( $p ));
    }
    else if (_spelled(type, "(* char)") && next &&
             _spelled(next, "(\"size_t\")")) {
      params.push($!Param{ TextField $p });
      args.push($!( x2cui_buffer($p) ));
      args.push($!( $p.capacity ));
      i++;
    }
    else if (_spelled(type, "(* const * const char)") && next &&
             _spelled(next, "(int)")) {
      params.push($!Param{ List $p });
      args.push($!( x2cui_strings($p) ));
      args.push($!( (int) $p.len() ));
      i++;
    }
    else if (_pointer(type) && (_spelled(Type.element(type), "(void)") ||
                                _function(Type.element(type)))) {
      // A void pointer and a callback pass as C.
      params.push($!Param{ $type $p });
      args.push($!( $p ));
    }
    else if (_const_pointer(type) && next && _spelled(next, "(int)")) {
      // An array of records and its count pass as C; the method form
      // supplies the count.
      pairs.push(params.len() - 1);
      params.push($!Param{ $type $p });
      args.push($!( $p ));
    }
    else if (_const_pointer(type)) {
      Type record = Type.element(type);
      params.push($!Param{ $record $p });
      args.push($!( &$p ));
    }
    else if (_pointer(type)) {
      Type value = Type.element(type);
      params.push($!Param{ $value &$p });
      args.push($!( &$p ));
    }
    else {
      params.push($!Param{ $type $p });
      args.push($!( $p ));
    }
  }
  List declared = params.list_free(), passed = args.list_free();
  String name = _method_name(function);
  List method = x2c_ident(name);
  List unit = _spelled(result, "(void)")
    ? $!Unit{ inline void Ui.$method(@declared) { $target(@passed); } }
    : $!Unit{ inline $result Ui.$method(@declared) =>
                $target(@passed); };
  Type last = types[count - 1];
  int options = count > 1 && _const_pointer(last) &&
                x2cui_option_record(Type.element(last));
  List form = _method_form(name, options || lowers, pairs.list_free());
  return form ? %($unit $form) : $(unit);
}

/* Whether `cui_value` lowers a value of the C type `type`: text, an enum,
   or another of CUI's types by value. */
meta static int _lowers(Type type) {
  if (Type.is_text(type) || Type.resolve(type) ~= %(enum *)) return 1;
  Var name = type.car();
  return name is <string> && ((String) name).startswith("cui_");
}

/** Defines the `Ui` method for the CUI function `$target`. */
macro Unit $x2cui.method(Name $target) { @x2cui_method($target) }

/*  Method forms

    A component whose last parameter is CUI's option record has a method
    form that takes the options as `name: value` arguments:

      ui.button("Add", variant: primary, icon: plus)
      ui.row (gap: 8, align: center) { ... }

    The form of a component is an Expression macro `$Ui.NAME`; the form of
    a block component, whose C functions are `cui_NAME_begin` and
    `cui_NAME_end`, is a decorator `$Ui.NAME`. Written in its own template,
    `ui.NAME(...)` is the method the form wraps. Each form is one of the two
    templates below, which takes its name from the method; its ordinary
    arguments are those before the first `name: value`. A component's
    form calls its method with the arguments `x2cui_arguments` returns, and
    a block's form calls its begin method through `x2cui_begin`; both read
    the method's parameter types and lower each value by its type; see
    x2cui-options.x.
*/

/* CUI's own block macros, `cui_NAME(ui, ...) { ... }`, which run their
   block between `cui_NAME_begin` and `cui_NAME_end`. Each has a block
   form. Those that CUI writes with `CUI__SCOPE_IF` run the block only
   while the begin call reports the block open. The node editor, its
   nodes, and the tree table are begin and end pairs that CUI gives no
   macro; they join the lists as CUI would write them. A table, a data
   grid, and a card stack have forms of their own in
   x2cui-containers.x. */
meta static List _scopes = %("node_content" "dockspace" "box" "row" "column"
  "card" "scroll" "split" "dialog_footer" "button_group" "reorder_item"
  "spotlight" "dock" "carousel" "carousel_slide" "card_stack_item"
  "menu_bar" "toolbar" "status_bar" "virtual_list" "node" "tree_table");
meta static List _openings = %("dock_panel" "popover" "menu" "context_menu"
  "dialog" "sheet" "accordion" "reasoning" "hover_card" "expandable_card"
  "user_menu" "menu_bar_menu" "inspector" "tree" "node_editor");

/** Returns the begin call of a block, `ui.NAME_begin(...)` with the
    arguments `x2cui_arguments` returns, as a test that is true while the
    block is open.
*/
meta List x2cui_begin(
  List ui, String block, List pairs, List options, List @args) {
  List begin = x2c_ident(%"$(block)_begin");
  List passed = x2cui_arguments(ui, %"$(block)_begin", pairs, options, @args);
  List call = $!( $ui.$begin(@passed) );
  return block in _openings ? call : $!( ($call, 1) );
}

/* The template of a component's form. `pairs` are the positions of its
   arrays whose count follows them; see `x2cui_arguments`. */
macro Unit $x2cui.widget(Name $method, Literal @pairs) {
  macro Expression $Ui.$method(Expr $ui, Expr @args, Entry @options) =>
    $ui.$method(@x2cui_arguments($ui, $method, $pairs, $options, @args));
}

/* The template of a block's form. The receiver is evaluated once; the end
   call is deferred, so it also runs when the block leaves early; a block
   whose begin call reports whether it is open runs only while it is
   open. */
macro Unit $x2cui.block(Name $block, Name $end, Literal @pairs) {
  macro Decorator $Ui.$block(
    Stmt $body, Expr $ui, Expr @args, Entry @options) {
    {
      typeof($ui) ui = $ui;
      if ($x2cui_begin(ui, $block, $pairs, $options, @args)) {
        defer ui.$end();
        $body
      }
    }
  }
}

/* A row and a column end as a box does. */
meta static String _end_method(String block) =>
  block == "row" || block == "column" ? "box_end" : %"$(block)_end";

/* The method form of `method`, whose arrays at `pairs` are followed by
   their counts. A block's begin method has a block form; another method
   has a component form when `lowered` is set, as it is when the method
   takes an option record, a value `x2cui_value` lowers, or an array.
   NULL when it has none. */
meta static List _method_form(String method, int lowered, List pairs) {
  String block = method.endswith("_begin") ? method[:method.len() - 6] : NULL;
  if (block && (block in _scopes || block in _openings))
    return Macro_apply(
      $x2cui.block, %($block $(_end_method(block)) @pairs));
  return (lowered || pairs) && !block
    ? Macro_apply($x2cui.widget, %($method @pairs)) : NULL;
}

/** Returns the method form of `method`, a `Ui` method written in x2c
    rather than generated, whose arrays at `pairs` are followed by their
    counts.
*/
meta List x2cui_form(String method, List pairs) {
  Type ui = $!Type{ Ui };
  List types = Type.parameters(Type.resolve_member(ui, method, 1)[2]).cdr();
  int lowered = 0;
  for (int i = 0; i < types.len(); i++) lowered |= _lowers(types[i]);
  List form = _method_form(method, lowered, pairs);
  return form ? $(form) : %();
}

