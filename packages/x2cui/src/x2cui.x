/*  x2cui.x -- CUI's immediate-mode components with ordinary x2c calls.

    CUI draws its own components. A program describes the screen with calls
    on every frame; CUI lays it out, handles the mouse and keyboard, and
    draws it in a window or into pixels. This package keeps CUI's C
    implementation and gives each component an x2c form:

      ui.button("Add", variant: primary, icon: plus)
      ui.row (gap: 8, align: center) { ... }
      ui.radial_gauge("cpu", 64, 0, 100, bands: [{to: 60, tone: success}])
      ui.card_stack (swiped, "deck", 3) { ... }

    A `name: value` row sets a field of the component's option record. A
    lower-case name is a short name for a CUI constant, chosen by the C
    type of its field or parameter: `primary`, `fill`, `plus`. An Array
    literal is a constant array of CUI's records, with its count. A block
    form runs its target between the begin and end calls, and a block that
    reports a result declares the name it is given.

    `Ui` is CUI's `cui_ctx *` and `App` is its `cui_app *`, so every raw
    CUI call takes them as they are. `Offscreen` draws with the software
    renderer into pixels, with no window. `TextField` holds text that a
    component edits in place. A collection such as `Reactions` keeps
    CUI's records in a `Block`: `Reactions.of([{...}, ...])` builds one,
    `reactions[i]` points at a record, and a component reads and writes
    its records in place. Labels are Strings, and a list of labels is a
    List; a CUI function that takes a `printf` format is a method that
    takes the format and x2c values: `ui.textf("%d items", n)`.

    This unit is the `x2cui` package entry: `import "x2cui"` reaches every
    nonstatic name as `x2cui__*` and every method form. The vendored
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

$cleanup.by(App, close);
$cleanup.by(Offscreen, close);

#include <stdlib.h>
#include <string.h>

// windows

/** Opens a window. Raises `<init-fail>` when CUI cannot create it. */
App App.open(cui_app_desc desc) {
  App app = cui_app_create(&desc);
  if (!app)
    raise %(init-fail (library "cui") (operation "cui_app_create")
            (reason "CUI did not create a window"));
  return app;
}

/** Opens a window from `name: value` rows of `cui_app_desc`, as in
    `App.open(title: "Mail", width: 420, height: 600)`. */
macro Expression $App.open(Entry @options) =>
  App.open($x2cui_record(%("cui_app_desc"), $options));

/** Presents the last frame, waits for input or animation, and begins the
    next frame. Returns false once the window has closed. The window's
    title bar takes the background color of the current theme.
*/
bool App.frame(App app) {
  Ui ui = cui_app_ui(app);
  cui_color color = cui_color_of(ui, CUI_COLOR_BACKGROUND);
  x2cui_title_bar(
    cui_app_native_window(app), cui_get_theme_mode(ui) == CUI_THEME_DARK,
    (unsigned) color.r << 16 | color.g << 8 | color.b);
  return cui_app_frame(app);
}

/** Returns the window's borrowed `Ui`, valid until the window closes. */
inline Ui App.ui(App app) => cui_app_ui(app);

/** Closes the window; idempotent on NULL, and returns NULL. */
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
Ui Offscreen.ui(Offscreen o) => o.ui;

/** Begins a frame one sixtieth of a second after the last. */
void Offscreen.begin(Offscreen o) {
  cui_begin_frame(o.ui, 1.0f / 60);
}

/** Ends the frame and renders it into the surface's pixels. */
void Offscreen.end(Offscreen o) {
  cui_end_frame(o.ui);
  const cui_draw_data *data = cui_get_draw_data(o.ui);
  if (data.width_px != o.width || data.height_px != o.height) {
    o.width = data.width_px;
    o.height = data.height_px;
    o.pixels = realloc(o.pixels, (size_t) o.width * o.height * 4);
  }
  o.commands = data.command_count;
  cui_sw_render(
    o.renderer, data, o.pixels, o.width, o.height, o.width * 4, CUI_SW_RGBA);
}

/** Returns how many draw commands the last frame produced. */
int Offscreen.commands(Offscreen o) => o.commands;

/** Writes the last frame as a PNG. Raises `<io-fail>` when it cannot. */
void Offscreen.write_png(Offscreen o, String path) {
  if (o.pixels &&
      cui_write_png(
        path, o.pixels, o.width, o.height, o.width * 4))
    return;
  raise %(io-fail (library "cui") (operation "cui_write_png")
          (path $path));
}

/** Releases the renderer, the `Ui`, and the pixels; returns NULL. */
Offscreen Offscreen.close(Offscreen o) {
  if (!o) return NULL;
  if (o.ui) cui_destroy(o.ui);
  if (o.renderer) cui_sw_destroy(o.renderer);
  free(o.pixels);
  free(o);
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
void Ui.textf(Ui u, String format, List @values) =>
  cui_textf(u, "%s", format.format(@values));

/// Formats `values` by `format` into the next slot of the current row.
void Ui.table_cell_textf(Ui u, String format, List @values) =>
  cui_table_cell_textf(u, "%s", format.format(@values));

/// Writes text formatted as `Ui.textf` formats it to a terminal's buffer.
void cui_terminal_buffer.printf(
  cui_terminal_buffer &terminal, String format, List @values) =>
  cui_terminal_printf(&terminal, "%s", format.format(@values));

/// Appends a line formatted as `Ui.textf` formats it to a log's buffer.
void cui_log_buffer.append(
  cui_log_buffer &log, cui_log_level level, String format, List @values) =>
  cui_log_append(&log, level, "%s", format.format(@values));

/// Edits the two numbers at `value` in an inspector row.
bool Ui.prop_vec2(Ui u, String label, float *value, cui_prop_opts opts) =>
  cui_prop_vec_ex(u, label, value, 2, &opts);

/// Edits the three numbers at `value` in an inspector row.
bool Ui.prop_vec3(Ui u, String label, float *value, cui_prop_opts opts) =>
  cui_prop_vec_ex(u, label, value, 3, &opts);

/// Edits the four numbers at `value` in an inspector row.
bool Ui.prop_vec4(Ui u, String label, float *value, cui_prop_opts opts) =>
  cui_prop_vec_ex(u, label, value, 4, &opts);

// The x axis labels of a chart are a List in x2c and two option fields in C.
static cui_chart_opts _labelled(cui_chart_opts opts, List labels) {
  if (labels) {
    opts.labels = labels.c_strings();
    opts.label_count = labels.len();
  }
  return opts;
}

/** Begins a tree node and returns true while it is open. A leaf has no
    open flag: pass NULL for `open` and set `.leaf` in `opts`.
*/
bool Ui.tree_begin(Ui u, String label, bool &?open, cui_tree_opts opts) =>
  open ? cui_tree_begin(u, label, &open, &opts)
       : cui_tree_begin(u, label, NULL, &opts);

/** Draws a table cell that holds a tree node, `depth` levels in. Returns
    true when the node is clicked. A leaf has no open flag: pass NULL for
    `open`.
*/
bool Ui.tree_cell(
  Ui u, String label, int depth, bool has_children, bool &?open,
  String icon) =>
  open ? cui_tree_cell(u, label, depth, has_children, &open, icon)
       : cui_tree_cell(u, label, depth, has_children, NULL, icon);

/** Draws a donut chart with one slice for each of `values`, named by the
    matching String of `labels`.
*/
void Ui.donut_chart(
  Ui u, String id, ArrayFloat values, List labels, cui_chart_opts opts) {
  cui_donut_chart_ex(
    u, id, (const float *) values.bytes, labels.c_strings(),
    (int) values.len(), &opts);
}

/** Draws `values` as a small line with no axes. */
void Ui.sparkline(
  Ui u, ArrayFloat values, cui_size width, float height, cui_color color) {
  cui_sparkline(
    u, (const float *) values.bytes, (int) values.len(), width, height,
    color);
}

/** Draws `length` one-character boxes that edit `code`, a field of at
    least `length + 1` bytes. Returns true when the code changes.
*/
bool Ui.otp_input(Ui u, String id, TextField code, int length) =>
  cui_otp_input(u, id, code.buffer, length);

/** Begins a list whose items the user drags into a new order. `order`
    holds the item indices in display order, and CUI rewrites it.
*/
void Ui.reorder_begin(Ui u, String id, ArrayInt order) {
  cui_reorder_begin(u, id, (int *) order.bytes, (int) order.len());
}

/** Draws a line chart of `count` series, with `labels` along the x axis,
    or NULL for none. The method form supplies the count of an array.
*/
void Ui.line_chart(
  Ui u, String id, const cui_series *series, int count, List labels,
  cui_chart_opts opts) {
  opts = _labelled(opts, labels);
  cui_line_chart_ex(u, id, series, count, &opts);
}

/** Draws a bar chart of `count` series, with `labels` along the x axis,
    or NULL for none. The method form supplies the count of an array.
*/
void Ui.bar_chart(
  Ui u, String id, const cui_series *series, int count, List labels,
  cui_chart_opts opts) {
  opts = _labelled(opts, labels);
  cui_bar_chart_ex(u, id, series, count, &opts);
}

// lists and tables

/* The items drawn so far in the innermost `ui.each` of this thread. A
   `Ui` belongs to one thread, so the trail does too. */
static _Thread_local ItemTrail item_trail;

/** Begins the passes of `ui.each` and returns the trail of the list it is
    in, which `Ui.each_end` restores.
*/
ItemTrail Ui.each_begin(Ui u) {
  ItemTrail outer = item_trail;
  item_trail = (ItemTrail){ .listing = true };
  return outer;
}

/** Ends the passes of `ui.each`. */
void Ui.each_end(Ui u, ItemTrail outer) {
  item_trail = outer;
}

/* What an item's painter needs: its id, its state, and whether it draws
   the hairline along its top edge. */
typedef struct ItemPaint {
  cui_id id;
  bool hovered, selected, rule;
} ItemPaint;

/* A quiet fill when selected or hovered, otherwise the hairline, and the
   focus ring while the item has keyboard focus. The canvas clips its
   painter, so the ring of CUI's color and width lies on the item's edge
   rather than outside it. */
static void _paint_item(cui_ctx *ui, cui_rect r, void *user) {
  ItemPaint *paint = user;
  _paint_item_fill(ui, r, paint);
  if (cui_focus_visible(ui, paint.id))
    cui_draw_rect_border(
      ui, r, CUI_CORNERS(10), (cui_color){},
      cui_token_color(ui, CUI_TOKEN_FOCUS_RING), 2);
}

static void _paint_item_fill(cui_ctx *ui, cui_rect r, ItemPaint *paint) {
  if (paint.selected)
    cui_draw_rect(
      ui, r, CUI_CORNERS(10), cui_token_color(ui, CUI_TOKEN_ACTIVE));
  else if (paint.hovered)
    cui_draw_rect(
      ui, r, CUI_CORNERS(10), cui_token_color(ui, CUI_TOKEN_HOVER));
  else if (paint.rule)
    cui_draw_rect(
      ui, (cui_rect){ r.x + 12, r.y, r.w - 24, 1 }, CUI_CORNERS(0),
      cui_token_color(ui, CUI_TOKEN_BORDER_SUBTLE));
}

/** Begins an interactive row of a list, a stack box the width of its
    parent, and returns what the pointer or the keyboard did to it. Tab
    reaches the row, and Enter or Space clicks it, as a button. The row
    draws its own fill when selected or hovered. Inside `ui.each`, it
    draws a hairline along its top edge unless it is the first item, it
    is selected, or the item before it is selected. A focused row draws
    the focus ring. `Ui.box_end` ends it.
*/
RowState Ui.item_begin(Ui u, RowOptions opts) {
  cui_box_begin(u, &(cui_box){ .dir = CUI_STACK, .width = CUI_FILL });
  bool rule = item_trail.listing && item_trail.items && !item_trail.selected &&
              !opts.selected;
  item_trail.items++;
  item_trail.selected = opts.selected;
  cui_id id = cui_make_id(u, "x2cui-item");
  bool *hovered = cui_state(u, id, sizeof(bool));
  ItemPaint paint = { id, *hovered, opts.selected, rule };
  cui_canvas_result result = cui_canvas_ex(
    u, "x2cui-item", CUI_FILL, CUI_FILL, _paint_item, &paint, sizeof paint,
    CUI_CANVAS_FOCUSABLE);
  *hovered = result.hovered;
  return (RowState){ result.hovered, result.pressed, result.clicked };
}

/** Begins a row of a table and returns what the pointer did to it: the
    hover and press its highlight shows, and its click.
*/
RowState Ui.table_row_begin(Ui u, RowOptions opts) {
  bool clicked = cui_table_row(u, opts.selected);
  return (RowState){ cui_table_row_hovered(u), cui_table_row_pressed(u),
                     clicked };
}

/// Fills the next cell of the current row with one string.
void Ui.cell_text(Ui u, String text) => cui_table_cell_text(u, text);

/// Draws the next cell of a data grid's or a tree table's row with one text.
void Ui.grid_cell_text(Ui u, String text) => cui_data_grid_cell_text(u, text);

/** Returns the field's writable text for a component that edits it. */
char *x2cui_buffer(TextField field) => field.buffer;

// enums in data

/* For each enum whose members data names by Symbol, the members in the
   order the enum declares them from 0, and `T.named`; tools/gen-arrays.py
   writes them from cui.h. */
/* gen-arrays: begin generated named enums */

static SymbolSet tone_names =
  %<neutral info success warning danger violet teal rose accent>;

/** Returns the `cui_tone` member `name` names, as `<info>` names
    `CUI_TONE_INFO`, for one kept in quoted data; a name that is
    not a member is `CUI_TONE_NEUTRAL`. */
cui_tone cui_tone.named(Symbol name) {
  int at = tone_names.index(name);
  return at < 0 ? CUI_TONE_NEUTRAL : (cui_tone) at;
}

static SymbolSet log_level_names =
  %<trace debug info warn error>;

/** Returns the `cui_log_level` member `name` names, as `<debug>` names
    `CUI_LOG_DEBUG`, for one kept in quoted data; a name that is
    not a member is `CUI_LOG_TRACE`. */
cui_log_level cui_log_level.named(Symbol name) {
  int at = log_level_names.index(name);
  return at < 0 ? CUI_LOG_TRACE : (cui_log_level) at;
}

/* gen-arrays: end generated named enums */

// records and collections

/* `T.of(name: value ...)` builds the CUI record `T`, each field lowered as
   an option is: `cui_reaction.of(icon: heart, count: 4)`. */
macro Unit $x2cui.record(Name $record) {
  macro Expression $$record.of(Entry @fields) => $x2cui_of($record, $fields);
}

/* `Collection.of([{...}, ...])` builds a collection of `$record` from an
   Array literal of `name: value` rows. A macro's name takes a `Name`
   hole and a declaration's type a `Type` hole, so the collection's form
   and its methods are two templates. */
macro Unit $x2cui.collection(Name $list, Name $record) {
  macro Expression $$list.of(Expr $rows) using $copy => ({
    Block $copy = Block.new(sizeof($record));
    Block.append($copy, $x2cui_rows($record, $rows), $x2cui_row_count($rows));
    $copy;
  });
}

/* A collection of the CUI record `$record`: its records packed in a
   `Block`, which a component reads and writes in place. `list[i]` is a
   pointer to a record, so `list[i].count += 1` changes it, and `foreach`
   yields pointers. */
macro Unit $x2cui.records(Type $record, Type $list) {
  /** Returns a pointer to record `index`, valid until the collection
      grows: `list[i].count += 1` changes the record in place. */
  inline $record *$list.getindex($list list, int index) =>
    &(($record *) ((Block) list).bytes)[index];

  /** Returns the records, for a raw CUI call, valid until it grows. */
  inline $record *$list.data($list list) => ($record *) ((Block) list).bytes;

  /** Returns how many records the collection holds. */
  inline int $list.len($list list) => (int) ((Block) list).length;

  /** Appends `record`. */
  void $list.push($list list, $record record) {
    Block.append((Block) list, &record, 1);
  }

  /** Inserts `record` before record `index`. */
  void $list.insert($list list, int index, $record record) {
    Block block = (Block) list;
    Block.append(block, &record, 1);
    $record *records = ($record *) block.bytes;
    size_t moved = (block.length - 1 - index) * sizeof(*records);
    memmove(records + index + 1, records + index, moved);
    records[index] = record;
  }

  /** Removes record `index`. */
  void $list.remove($list list, int index) {
    Block block = (Block) list;
    $record *records = ($record *) block.bytes;
    size_t moved = (block.length - 1 - index) * sizeof(*records);
    memmove(records + index, records + index + 1, moved);
    block.length--;
  }

  /** The cursor `foreach (T *r in list)` uses: it yields a pointer to
      each record, so the loop changes records in place. */
  int $list.try_next($list list, int &cursor, $record *&out) {
    if (cursor >= (int) ((Block) list).length) return 0;
    out = &(($record *) ((Block) list).bytes)[cursor++];
    return 1;
  }
}

/** Makes room for one more record past the end of `records`, which an
    editor that grows its array types into, zeroed, and returns how many
    records `records` holds: the live count an editor takes.
*/
int x2cui_spare(Block records) {
  size_t used = records.length;
  if (records.cap > used) return (int) used;
  Block.reserve(records, used + 8);
  size_t spare = (records.cap - used) * records.width;
  memset(records.bytes + used * records.width, 0, spare);
  return (int) used;
}

/* gen-arrays: begin generated records */

$x2cui.record(cui_vec2); $x2cui.record(cui_rect); $x2cui.record(cui_date);
$x2cui.record(cui_tour_step); $x2cui.record(cui_table_column);
$x2cui.record(cui_table_sort); $x2cui.record(cui_image_view);
$x2cui.record(cui_command); $x2cui.record(cui_choice);
$x2cui.record(cui_reaction); $x2cui.record(cui_speed_action);
$x2cui.record(cui_swipe_action); $x2cui.record(cui_grid_column);
$x2cui.record(cui_filter_field); $x2cui.record(cui_tree_node);
$x2cui.record(cui_tree_table_events); $x2cui.record(cui_file_entry);
$x2cui.record(cui_text_mark); $x2cui.record(cui_diff_row);
$x2cui.record(cui_diff_hunk); $x2cui.record(cui_diff_stats);
$x2cui.record(cui_diff_range); $x2cui.record(cui_presence_user);
$x2cui.record(cui_ticker_item); $x2cui.record(cui_viz_item);
$x2cui.record(cui_sankey_link); $x2cui.record(cui_scatter_series);
$x2cui.record(cui_gauge_band); $x2cui.record(cui_candle);
$x2cui.record(cui_tab_bar_item); $x2cui.record(cui_now_playing);
$x2cui.record(cui_plan_step); $x2cui.record(cui_source);
$x2cui.record(cui_prompt_suggestion); $x2cui.record(cui_model);
$x2cui.record(cui_kanban_move); $x2cui.record(cui_cal_event);
$x2cui.record(cui_month_event); $x2cui.record(cui_gantt_task);
$x2cui.record(cui_toc_item); $x2cui.record(cui_check_step);
$x2cui.record(cui_date_range); $x2cui.record(cui_key_combo);
$x2cui.record(cui_node_view); $x2cui.record(cui_doc_tab);
$x2cui.record(cui_log_line); $x2cui.record(cui_log_buffer);
$x2cui.record(cui_terminal_line); $x2cui.record(cui_terminal_buffer);
$x2cui.record(cui_hex_range); $x2cui.record(cui_hex_selection);
$x2cui.record(cui_flame_span); $x2cui.record(cui_flame_view);
$x2cui.record(cui_curve_key); $x2cui.record(cui_gradient_stop);
$x2cui.record(cui_timeline_clip); $x2cui.record(cui_timeline_track);
$x2cui.record(cui_timeline_view); $x2cui.record(cui_kv_pair);
$x2cui.record(cui_diagnostic); $x2cui.record(cui_pipeline_job);
$x2cui.record(cui_query_field); $x2cui.record(cui_query_node);
$x2cui.record(cui_keymap_binding); $x2cui.record(cui_commit);
$x2cui.record(cui_graph_node); $x2cui.record(cui_graph_edge);
$x2cui.record(cui_net_request); $x2cui.record(cui_trace_track);
$x2cui.record(cui_trace_span); $x2cui.record(cui_trace_marker);
$x2cui.record(cui_trace_view); $x2cui.record(cui_regex_match);
$x2cui.record(cui_test_item); $x2cui.record(cui_stack_frame);
$x2cui.record(cui_uptime_service); $x2cui.record(cui_histogram_series);
$x2cui.record(cui_coverage_file); $x2cui.record(cui_blame_commit);
$x2cui.record(cui_feature_flag); $x2cui.record(cui_api_param);
$x2cui.record(cui_api_endpoint);
typedef Block CalEvents;
$x2cui.records(cui_cal_event, CalEvents);
$x2cui.collection(CalEvents, cui_cal_event);
typedef Block Candles;
$x2cui.records(cui_candle, Candles);
$x2cui.collection(Candles, cui_candle);
typedef Block CheckSteps;
$x2cui.records(cui_check_step, CheckSteps);
$x2cui.collection(CheckSteps, cui_check_step);
typedef Block CurveKeys;
$x2cui.records(cui_curve_key, CurveKeys);
$x2cui.collection(CurveKeys, cui_curve_key);
typedef Block DocTabs;
$x2cui.records(cui_doc_tab, DocTabs);
$x2cui.collection(DocTabs, cui_doc_tab);
typedef Block FeatureFlags;
$x2cui.records(cui_feature_flag, FeatureFlags);
$x2cui.collection(FeatureFlags, cui_feature_flag);
typedef Block FlameSpans;
$x2cui.records(cui_flame_span, FlameSpans);
$x2cui.collection(FlameSpans, cui_flame_span);
typedef Block GanttTasks;
$x2cui.records(cui_gantt_task, GanttTasks);
$x2cui.collection(GanttTasks, cui_gantt_task);
typedef Block GradientStops;
$x2cui.records(cui_gradient_stop, GradientStops);
$x2cui.collection(GradientStops, cui_gradient_stop);
typedef Block KvPairs;
$x2cui.records(cui_kv_pair, KvPairs);
$x2cui.collection(KvPairs, cui_kv_pair);
typedef Block MonthEvents;
$x2cui.records(cui_month_event, MonthEvents);
$x2cui.collection(MonthEvents, cui_month_event);
typedef Block PlanSteps;
$x2cui.records(cui_plan_step, PlanSteps);
$x2cui.collection(PlanSteps, cui_plan_step);
typedef Block PromptSuggestions;
$x2cui.records(cui_prompt_suggestion, PromptSuggestions);
$x2cui.collection(PromptSuggestions, cui_prompt_suggestion);
typedef Block QueryFields;
$x2cui.records(cui_query_field, QueryFields);
$x2cui.collection(QueryFields, cui_query_field);
typedef Block QueryNodes;
$x2cui.records(cui_query_node, QueryNodes);
$x2cui.collection(QueryNodes, cui_query_node);
typedef Block Reactions;
$x2cui.records(cui_reaction, Reactions);
$x2cui.collection(Reactions, cui_reaction);
typedef Block Series;
$x2cui.records(cui_series, Series);
$x2cui.collection(Series, cui_series);
typedef Block Sources;
$x2cui.records(cui_source, Sources);
$x2cui.collection(Sources, cui_source);
typedef Block SpeedActions;
$x2cui.records(cui_speed_action, SpeedActions);
$x2cui.collection(SpeedActions, cui_speed_action);
typedef Block TimelineTracks;
$x2cui.records(cui_timeline_track, TimelineTracks);
$x2cui.collection(TimelineTracks, cui_timeline_track);
typedef Block TocItems;
$x2cui.records(cui_toc_item, TocItems);
$x2cui.collection(TocItems, cui_toc_item);
typedef Block TourSteps;
$x2cui.records(cui_tour_step, TourSteps);
$x2cui.collection(TourSteps, cui_tour_step);
typedef Block TraceSpans;
$x2cui.records(cui_trace_span, TraceSpans);
$x2cui.collection(TraceSpans, cui_trace_span);
typedef Block TraceTracks;
$x2cui.records(cui_trace_track, TraceTracks);
$x2cui.collection(TraceTracks, cui_trace_track);
typedef Block TreeNodes;
$x2cui.records(cui_tree_node, TreeNodes);
$x2cui.collection(TreeNodes, cui_tree_node);
typedef Block Vec2s;
$x2cui.records(cui_vec2, Vec2s);
$x2cui.collection(Vec2s, cui_vec2);
typedef Block VizItems;
$x2cui.records(cui_viz_item, VizItems);
$x2cui.collection(VizItems, cui_viz_item);
typedef Block ScatterSeries;
$x2cui.records(cui_scatter_series, ScatterSeries);
$x2cui.collection(ScatterSeries, cui_scatter_series);
/* gen-arrays: end generated records */

// helpers over raw calls

/** Returns the query parameters of `url`, up to 32, as key-value pairs,
    all on. */
KvPairs KvPairs.of_url(String url) {
  Block pairs = Block.new(sizeof(cui_kv_pair));
  Block.reserve(pairs, 32);
  pairs.length = cui_url_params(url, (cui_kv_pair *) pairs.bytes, 32);
  return pairs;
}

/** Replaces the query of the URL in `field` with the pairs of `pairs` that
    are on. */
void TextField.set_url_params(TextField field, KvPairs pairs) {
  cui_url_set_params(field.buffer, field.capacity, pairs.data(), pairs.len());
}

/** Returns the query `nodes` builds over `fields`, as a sentence. */
String QueryFields.text(QueryFields fields, QueryNodes nodes) {
  char text[256];
  cui_query_text(
    fields.data(), fields.len(), nodes.data(), nodes.len(), text, sizeof text);
  return String.new(text);
}

/* One native array for each List of Strings a component has been given,
   keyed by the List. A List is canonical and lives as long as the pool
   that interned it, so equal Lists share one entry and an entry never goes
   stale; the array adds a constant factor to what the pool already holds.
   Looking up an existing List allocates nothing. The table is shared by
   the process and is not locked, so one thread draws; see the README. */
static Map string_arrays = {};

// The array of an empty List, which is NULL; it allocates nothing.
static const char *no_strings[] = { NULL };

/** Returns the Strings of `items` as the array a component reads. CUI may
    read the array until the frame ends, so the array is kept and is built
    once for each distinct List. A List interned inside a caller's
    `Pool.open` bracket loses its identity at `Pool.close`, and its entry is
    not used again.
*/
const char *const *List.c_strings(List items) {
  if (!items) return no_strings;
  Var found;
  if (string_arrays.try_get(items, found)) return found.pointer();
  const char **names = malloc((items.len() + 1) * sizeof *names);
  int index = 0;
  foreach (String item in items) names[index++] = item;
  names[index] = NULL;
  string_arrays[items] = Var.new(<p48>, names);
  return names;
}

/* Each row is a CUI function whose parameters follow the generator's
   conventions. `expand` defines the `Ui` method for each one. */
expand %(
  cui_heading cui_destroy cui_set_renderer cui_set_viewport cui_viewport_size
  cui_dpi_scale cui_begin_frame cui_end_frame cui_needs_redraw
  cui_next_wakeup cui_request_redraw cui_request_wakeup cui_time
  cui_delta_time cui_frame_count cui_input_mouse_move cui_input_mouse_button
  cui_input_mouse_leave cui_input_scroll cui_input_key cui_input_text
  cui_input_focus cui_input_file_hover cui_input_file_drop
  cui_dropped_file_count cui_dropped_file cui_file_drag_active
  cui_set_platform cui_get_cursor cui_key_pressed cui_key_down cui_shortcut
  cui_key_mods cui_mouse_pos cui_mouse_down cui_mouse_clicked
  cui_wants_keyboard cui_wants_mouse cui_set_theme cui_get_theme_mode
  cui_set_accent cui_get_accent cui_theme_get cui_set_reduced_motion
  cui_color_of cui_set_strings cui_get_strings cui_token_color
  cui_font_load_memory cui_font_load_file cui_font_set_role
  cui_font_add_fallback cui_measure_text cui_box_begin cui_box_end
  cui_row_begin cui_column_begin cui_spacer cui_gap cui_separator
  cui_card_begin cui_card_end cui_scroll_begin cui_scroll_end cui_scroll_to
  cui_split_begin cui_split_next cui_split_end cui_make_id cui_push_id
  cui_push_id_int cui_pop_id cui_last_id cui_last_rect cui_get_rect
  cui_last_hovered cui_is_disabled cui_push_disabled cui_pop_disabled
  cui_text_ex cui_label cui_secondary cui_muted cui_code cui_kbd cui_link
  cui_icon cui_button_ex cui_icon_button_ex cui_segmented_ex cui_checkbox_ex
  cui_switch_ex cui_radio_ex cui_radio_group cui_slider_ex cui_range_slider
  cui_rating cui_chip_ex cui_input_ex cui_textarea_ex cui_search_ex
  cui_number_ex cui_select_ex cui_calendar cui_date_picker_ex
  cui_color_picker cui_tabs_ex cui_nav_item_ex cui_nav_section cui_breadcrumb
  cui_pagination cui_stepper cui_popover_begin cui_popover_end
  cui_popover_open cui_popover_close cui_popover_toggle cui_popover_is_open
  cui_menu_begin cui_menu_end cui_context_menu_begin cui_context_menu_end
  cui_menu_item_ex cui_menu_separator cui_menu_label cui_tooltip
  cui_dialog_begin cui_dialog_end cui_dialog_footer_begin
  cui_dialog_footer_end cui_sheet_begin cui_sheet_end
  cui_toast_action_clicked cui_toast_ex cui_toast_dismiss cui_alert_ex
  cui_progress_ex cui_spinner cui_skeleton cui_badge_ex cui_avatar_ex
  cui_avatar_group cui_empty_state_ex cui_metric_ex cui_meter
  cui_accordion_begin cui_accordion_end cui_tree_end cui_tree_clicked
  cui_list_item_ex cui_virtual_list_begin cui_virtual_list_end
  cui_table_begin_ex cui_table_row cui_table_row_hovered cui_table_row_pressed
  cui_table_cell cui_table_cell_text
  cui_table_end cui_gauge cui_image_create cui_image_load cui_image_destroy
  cui_image_ex cui_image_viewer_ex cui_cropper_ex cui_command_palette
  cui_radio_cards_ex cui_tag_input_ex cui_button_group_begin
  cui_button_group_end cui_copy_button cui_hold_button_ex
  cui_password_strength cui_timeline_item_ex cui_reorder_end
  cui_reorder_item_begin cui_reorder_item_end cui_progress_ring
  cui_split_button_ex cui_confirm_button_ex cui_status_button_ex
  cui_theme_switcher cui_theme_toggle cui_user_menu_begin cui_user_menu_end
  cui_swipe_item_end cui_data_grid_begin_ex cui_data_grid_row
  cui_data_grid_cell_text cui_data_grid_end cui_data_grid_cell
  cui_data_grid_cell_edit cui_data_grid_edit cui_tree_table_row
  cui_tree_table_name cui_tree_table_end cui_tree_table_depth cui_path_bar_ex
  cui_path_bar_menu_begin cui_path_bar_menu_end cui_file_browser_ex
  cui_file_picker_ex cui_terminal_ex cui_code_block_ex cui_json_view_ex
  cui_markdown_ex cui_code_editor_ex cui_code_editor_goto
  cui_code_editor_select cui_code_editor_find cui_diff_view_ex
  cui_chat_message_ex cui_chat_divider cui_typing_indicator cui_comment_ex
  cui_carousel_begin cui_carousel_slide_begin cui_carousel_slide_end
  cui_carousel_end cui_image_compare_ex cui_card_stack_begin
  cui_card_stack_item_begin cui_card_stack_item_end cui_card_stack_end
  cui_counter_ex cui_radial_gauge_ex cui_shimmer_text_ex cui_typewriter_ex
  cui_text_reveal_ex cui_word_rotate_ex cui_number_roll_ex
  cui_gradient_text_ex cui_spotlight_begin cui_spotlight_end cui_loader_ex
  cui_dock_begin cui_dock_item_ex cui_dock_separator cui_dock_end
  cui_control_tile_ex cui_now_playing_ex cui_reasoning_begin
  cui_reasoning_end cui_tool_call_ex cui_agent_status_ex cui_citation
  cui_context_meter_ex cui_response_actions_ex cui_chat_composer_ex
  cui_voice_orb_ex cui_kanban_begin cui_kanban_card_begin cui_kanban_card_end
  cui_kanban_column_end cui_kanban_end cui_kanban_column_begin_ex
  cui_hover_card_begin cui_hover_card_end cui_confirm_popover_ex
  cui_expandable_text_ex cui_expandable_card_begin cui_expandable_card_end
  cui_toc_anchor cui_banner_ex cui_countdown_ex cui_range_calendar
  cui_date_range_picker_ex cui_time_picker_ex cui_wheel_picker_ex
  cui_time_dial cui_ruler_slider_ex cui_knob_ex cui_fader_ex
  cui_signature_pad_ex cui_signature_clear cui_dropzone_ex cui_avatar_upload
  cui_inline_edit_ex cui_scrub_ex cui_money_input_ex cui_shortcut_recorder_ex
  cui_shortcut_label cui_node_end cui_node_link cui_node_link_created
  cui_node_link_removed cui_node_deleted cui_node_editor_end
  cui_node_editor_begin_ex cui_node_begin_ex cui_node_input_ex
  cui_node_output_ex cui_node_content_begin cui_node_content_end
  cui_menu_bar_begin cui_menu_bar_end cui_menu_bar_menu_begin
  cui_menu_bar_menu_end cui_toolbar_begin cui_toolbar_end
  cui_toolbar_button_ex cui_toolbar_separator cui_toolbar_spacer
  cui_status_bar_begin cui_status_bar_end cui_status_bar_spacer
  cui_status_bar_text_ex cui_status_bar_item_ex cui_status_bar_progress_ex
  cui_dock_panel_end cui_dockspace_end cui_dockspace_begin_ex
  cui_dock_panel_begin_ex cui_dock_save cui_dock_load cui_inspector_group
  cui_inspector_end cui_inspector_begin_ex cui_prop_float_ex cui_prop_int_ex
  cui_prop_text_ex cui_prop_bool_ex cui_prop_enum_ex cui_prop_color_ex
  cui_log_view_ex cui_emoji_font_load_file cui_emoji_font_load_memory
  cui_emoji_font_load_system cui_emoji_supported cui_draw_emoji cui_emoji
  cui_emoji_picker_ex cui_hex_view_goto cui_flame_span_rect
  cui_schedule_picker_ex cui_cron_describe cui_regex_tester_ex
  cui_request_bar_ex cui_response_status cui_draw_rect cui_draw_rect_border
  cui_draw_rect_gradient cui_draw_shadow cui_draw_line cui_draw_circle
  cui_draw_arc cui_draw_text cui_draw_icon cui_draw_image cui_push_clip
  cui_pop_clip cui_canvas cui_state cui_state_on_free cui_animate
  cui_animate_spring cui_get_draw_data)
macro Unit(Name $target) { $x2cui.method($target); }

// Components that take arrays. Rerun tools/gen-arrays.py to refresh these.

/* gen-arrays: begin generated methods */

/** Calls `cui_tour_ex`. */
inline int Ui.tour(
  Ui u, String id, const cui_tour_step *steps, int count, int &step,
  cui_tour_opts opts) =>
  cui_tour_ex(u, id, steps, count, &step, &opts);

/** Calls `cui_toggle_group_ex`. */
inline bool Ui.toggle_group(
  Ui u, String id, List labels, bool *values, cui_toggle_group_opts opts) =>
  cui_toggle_group_ex(u, id, labels.c_strings(), labels.len(), values, &opts);

/** Calls `cui_reactions`. */
inline int Ui.reactions(Ui u, String id, cui_reaction *items, int count) =>
  cui_reactions(u, id, items, count);

/** Calls `cui_speed_dial_ex`. */
inline int Ui.speed_dial(
  Ui u, String id, const cui_speed_action *actions, int count,
  cui_speed_dial_opts opts) =>
  cui_speed_dial_ex(u, id, actions, count, &opts);

/** Calls `cui_swipe_item_begin`. */
inline void Ui.swipe_item_begin(
  Ui u, String id, const cui_swipe_action *left, int left_count,
  const cui_swipe_action *right, int right_count) =>
  cui_swipe_item_begin(u, id, left, left_count, right, right_count);

/** Calls `cui_filter_bar`. */
inline bool Ui.filter_bar(
  Ui u, String id, const cui_filter_field *fields, int count,
  uint32_t *selected, TextField search) =>
  cui_filter_bar(
    u, id, fields, count, selected, x2cui_buffer(search), search.capacity);

/** Calls `cui_tree_table_begin_ex`. */
inline void Ui.tree_table_begin(
  Ui u, String id, const cui_grid_column *columns, int column_count,
  cui_tree_node *nodes, int node_count, cui_tree_table_opts opts) =>
  cui_tree_table_begin_ex(
    u, id, columns, column_count, nodes, node_count, &opts);

/** Calls `cui_diff_view_rows`. */
inline int Ui.diff_view_rows(
  Ui u, String id, cui_diff_row *rows, int first, int cap) =>
  cui_diff_view_rows(u, id, rows, first, cap);

/** Calls `cui_presence`. */
inline void Ui.presence(
  Ui u, String id, const cui_presence_user *users, int count, int max_visible,
  float size) =>
  cui_presence(u, id, users, count, max_visible, size);

/** Calls `cui_ticker_ex`. */
inline void Ui.ticker(
  Ui u, String id, const cui_ticker_item *items, int count,
  cui_ticker_opts opts) =>
  cui_ticker_ex(u, id, items, count, &opts);

/** Calls `cui_heatmap_ex`. */
inline int Ui.heatmap(
  Ui u, String id, const float *values, int rows, int cols,
  cui_heatmap_opts opts) =>
  cui_heatmap_ex(u, id, values, rows, cols, &opts);

/** Calls `cui_calendar_heatmap_ex`. */
inline int Ui.calendar_heatmap(
  Ui u, String id, cui_date start, const float *values, int days,
  cui_calendar_heatmap_opts opts) =>
  cui_calendar_heatmap_ex(u, id, start, values, days, &opts);

/** Calls `cui_treemap_ex`. */
inline int Ui.treemap(
  Ui u, String id, const cui_viz_item *items, int count,
  cui_treemap_opts opts) =>
  cui_treemap_ex(u, id, items, count, &opts);

/** Calls `cui_radar_chart_ex`. */
inline int Ui.radar_chart(
  Ui u, String id, const cui_series *series, int count, List axes,
  cui_radar_opts opts) =>
  cui_radar_chart_ex(
    u, id, series, count, axes.c_strings(), axes.len(), &opts);

/** Calls `cui_funnel_ex`. */
inline int Ui.funnel(
  Ui u, String id, const cui_viz_item *stages, int count,
  cui_funnel_opts opts) =>
  cui_funnel_ex(u, id, stages, count, &opts);

/** Calls `cui_sankey_ex`. */
inline int Ui.sankey(
  Ui u, String id, List nodes, const cui_sankey_link *links, int link_count,
  cui_sankey_opts opts) =>
  cui_sankey_ex(
    u, id, nodes.c_strings(), nodes.len(), links, link_count, &opts);

/** Calls `cui_waffle_ex`. */
inline int Ui.waffle(
  Ui u, String id, const cui_viz_item *items, int count,
  cui_waffle_opts opts) =>
  cui_waffle_ex(u, id, items, count, &opts);

/** Calls `cui_split_bar_ex`. */
inline int Ui.split_bar(
  Ui u, String id, const cui_viz_item *items, int count,
  cui_split_bar_opts opts) =>
  cui_split_bar_ex(u, id, items, count, &opts);

/** Calls `cui_bar_list_ex`. */
inline int Ui.bar_list(
  Ui u, String id, const cui_viz_item *items, int count,
  cui_bar_list_opts opts) =>
  cui_bar_list_ex(u, id, items, count, &opts);

/** Calls `cui_activity_rings_ex`. */
inline int Ui.activity_rings(
  Ui u, String id, const cui_viz_item *rings, int count,
  cui_rings_opts opts) =>
  cui_activity_rings_ex(u, id, rings, count, &opts);

/** Calls `cui_scatter_chart_ex`. */
inline int Ui.scatter_chart(
  Ui u, String id, const cui_scatter_series *series, int count,
  cui_scatter_opts opts) =>
  cui_scatter_chart_ex(u, id, series, count, &opts);

/** Calls `cui_candlestick_ex`. */
inline int Ui.candlestick(
  Ui u, String id, const cui_candle *candles, int count,
  cui_candlestick_opts opts) =>
  cui_candlestick_ex(u, id, candles, count, &opts);

/** Calls `cui_tab_bar_ex`. */
inline bool Ui.tab_bar(
  Ui u, String id, const cui_tab_bar_item *items, int count, int &selected,
  cui_tab_bar_opts opts) =>
  cui_tab_bar_ex(u, id, items, count, &selected, &opts);

/** Calls `cui_waveform_ex`. */
inline bool Ui.waveform(
  Ui u, String id, const float *peaks, int count, float &progress,
  cui_waveform_opts opts) =>
  cui_waveform_ex(u, id, peaks, count, &progress, &opts);

/** Calls `cui_agent_plan_ex`. */
inline int Ui.agent_plan(
  Ui u, String id, const cui_plan_step *steps, int count,
  cui_agent_plan_opts opts) =>
  cui_agent_plan_ex(u, id, steps, count, &opts);

/** Calls `cui_source_list`. */
inline int Ui.source_list(
  Ui u, String id, const cui_source *sources, int count) =>
  cui_source_list(u, id, sources, count);

/** Calls `cui_prompt_suggestions_ex`. */
inline int Ui.prompt_suggestions(
  Ui u, String id, const cui_prompt_suggestion *items, int count,
  cui_prompt_suggestions_opts opts) =>
  cui_prompt_suggestions_ex(u, id, items, count, &opts);

/** Calls `cui_model_picker_ex`. */
inline bool Ui.model_picker(
  Ui u, String id, const cui_model *models, int count, int &selected,
  cui_model_picker_opts opts) =>
  cui_model_picker_ex(u, id, models, count, &selected, &opts);

/** Calls `cui_week_calendar_ex`. */
inline int Ui.week_calendar(
  Ui u, String id, cui_date week_start, cui_cal_event *events, int count,
  cui_week_opts opts) =>
  cui_week_calendar_ex(u, id, week_start, events, count, &opts);

/** Calls `cui_month_calendar_ex`. */
inline cui_month_result Ui.month_calendar(
  Ui u, String id, cui_date &month, const cui_month_event *events, int count,
  cui_month_opts opts) =>
  cui_month_calendar_ex(u, id, &month, events, count, &opts);

/** Calls `cui_gantt_ex`. */
inline int Ui.gantt(
  Ui u, String id, cui_gantt_task *tasks, int count, cui_date origin, int days,
  cui_gantt_opts opts) =>
  cui_gantt_ex(u, id, tasks, count, origin, days, &opts);

/** Calls `cui_toc`. */
inline int Ui.toc(
  Ui u, String scroll_id, const cui_toc_item *items, int count) =>
  cui_toc(u, scroll_id, items, count);

/** Calls `cui_checklist_ex`. */
inline int Ui.checklist(
  Ui u, String id, cui_check_step *steps, int count,
  cui_checklist_opts opts) =>
  cui_checklist_ex(u, id, steps, count, &opts);

/** Calls `cui_multi_select_ex`. */
inline bool Ui.multi_select(
  Ui u, String id, List items, bool *selected, cui_multi_select_opts opts) =>
  cui_multi_select_ex(u, id, items.c_strings(), items.len(), selected, &opts);

/** Calls `cui_histogram_slider_ex`. */
inline bool Ui.histogram_slider(
  Ui u, String label, const float *bins, int bin_count, float &lo, float &hi,
  float min, float max, cui_histogram_opts opts) =>
  cui_histogram_slider_ex(
    u, label, bins, bin_count, &lo, &hi, min, max, &opts);

/** Calls `cui_level_meter_ex`. */
inline bool Ui.level_meter(
  Ui u, String id, const float *levels, int channels,
  cui_level_meter_opts opts) =>
  cui_level_meter_ex(u, id, levels, channels, &opts);

/** Calls `cui_doc_tabs_ex`. */
inline cui_doc_tabs_result Ui.doc_tabs(
  Ui u, String id, const cui_doc_tab *tabs, int count, int &selected,
  cui_doc_tabs_opts opts) =>
  cui_doc_tabs_ex(u, id, tabs, count, &selected, &opts);

/** Calls `cui_prop_vec_ex`. */
inline bool Ui.prop_vec(
  Ui u, String label, float *value, int components, cui_prop_opts opts) =>
  cui_prop_vec_ex(u, label, value, components, &opts);

/** Calls `cui_hex_view_ex`. */
inline cui_hex_result Ui.hex_view(
  Ui u, String id, const uint8_t *data, size_t size, cui_hex_selection &sel,
  cui_hex_view_opts opts) =>
  cui_hex_view_ex(u, id, data, size, &sel, &opts);

/** Calls `cui_flame_graph_ex`. */
inline cui_flame_result Ui.flame_graph(
  Ui u, String id, const cui_flame_span *spans, int count,
  cui_flame_view &view, int &selected, cui_flame_opts opts) =>
  cui_flame_graph_ex(u, id, spans, count, &view, &selected, &opts);

/** Calls `cui_curve_editor_ex` on the records of `keys`,
    which grow in place. */
cui_curve_result Ui.curve_editor(
  Ui u, String id, Block keys, cui_curve_opts opts) {
  int count = x2cui_spare(keys);
  cui_curve_result result = cui_curve_editor_ex(
    u, id, (cui_curve_key *) keys.bytes, &count, (int) keys.cap, &opts);
  keys.length = count;
  return result;
}

/** Calls `cui_gradient_editor_ex` on the records of `stops`,
    which grow in place. */
cui_gradient_result Ui.gradient_editor(
  Ui u, String id, Block stops, cui_gradient_opts opts) {
  int count = x2cui_spare(stops);
  cui_gradient_result result = cui_gradient_editor_ex(
    u, id, (cui_gradient_stop *) stops.bytes, &count, (int) stops.cap, &opts);
  stops.length = count;
  return result;
}

/** Calls `cui_timeline_editor_ex`. */
inline cui_timeline_editor_result Ui.timeline_editor(
  Ui u, String id, cui_timeline_track *tracks, int count, float &time,
  cui_timeline_editor_opts opts) =>
  cui_timeline_editor_ex(u, id, tracks, count, &time, &opts);

/** Calls `cui_kv_editor_ex` on the records of `pairs`,
    which grow in place. */
bool Ui.kv_editor(Ui u, String id, Block pairs, cui_kv_editor_opts opts) {
  int count = x2cui_spare(pairs);
  bool result = cui_kv_editor_ex(
    u, id, (cui_kv_pair *) pairs.bytes, &count, (int) pairs.cap, &opts);
  pairs.length = count;
  return result;
}

/** Calls `cui_problems_ex`. */
inline cui_problems_result Ui.problems(
  Ui u, String id, const cui_diagnostic *diags, int count,
  cui_problems_opts opts) =>
  cui_problems_ex(u, id, diags, count, &opts);

/** Calls `cui_pipeline_ex`. */
inline cui_pipeline_result Ui.pipeline(
  Ui u, String id, List stages, const cui_pipeline_job *jobs, int job_count,
  cui_pipeline_opts opts) =>
  cui_pipeline_ex(
    u, id, stages.c_strings(), stages.len(), jobs, job_count, &opts);

/** Calls `cui_query_builder_ex` on the records of `nodes`,
    which grow in place. */
bool Ui.query_builder(
  Ui u, String id, const cui_query_field *fields, int field_count, Block nodes,
  cui_query_opts opts) {
  int count = x2cui_spare(nodes);
  bool result = cui_query_builder_ex(
    u, id, fields, field_count, (cui_query_node *) nodes.bytes, &count,
    (int) nodes.cap, &opts);
  nodes.length = count;
  return result;
}

/** Calls `cui_keymap_ex`. */
inline cui_keymap_result Ui.keymap(
  Ui u, String id, const cui_keymap_binding *bindings, int count,
  cui_keymap_opts opts) =>
  cui_keymap_ex(u, id, bindings, count, &opts);

/** Calls `cui_commit_graph_ex`. */
inline cui_commit_graph_result Ui.commit_graph(
  Ui u, String id, const cui_commit *commits, int count,
  cui_commit_graph_opts opts) =>
  cui_commit_graph_ex(u, id, commits, count, &opts);

/** Calls `cui_graph_view_ex`. */
inline cui_graph_result Ui.graph_view(
  Ui u, String id, const cui_graph_node *nodes, int node_count,
  const cui_graph_edge *edges, int edge_count, cui_graph_opts opts) =>
  cui_graph_view_ex(u, id, nodes, node_count, edges, edge_count, &opts);

/** Calls `cui_waterfall_ex`. */
inline cui_waterfall_result Ui.waterfall(
  Ui u, String id, const cui_net_request *requests, int count,
  cui_waterfall_opts opts) =>
  cui_waterfall_ex(u, id, requests, count, &opts);

/** Calls `cui_trace_view_ex`. */
inline cui_trace_result Ui.trace_view(
  Ui u, String id, cui_trace_track *tracks, int track_count,
  const cui_trace_span *spans, int span_count, cui_trace_view &view,
  int &selected, cui_trace_opts opts) =>
  cui_trace_view_ex(
    u, id, tracks, track_count, spans, span_count, &view, &selected, &opts);

/** Calls `cui_test_explorer_ex`. */
inline cui_test_explorer_result Ui.test_explorer(
  Ui u, String id, const cui_test_item *items, int count,
  cui_test_explorer_opts opts) =>
  cui_test_explorer_ex(u, id, items, count, &opts);

/** Calls `cui_stack_trace_ex`. */
inline cui_stack_trace_result Ui.stack_trace(
  Ui u, String id, const cui_stack_frame *frames, int count,
  cui_stack_trace_opts opts) =>
  cui_stack_trace_ex(u, id, frames, count, &opts);

/** Calls `cui_uptime_ex`. */
inline cui_uptime_result Ui.uptime(
  Ui u, String id, const cui_uptime_service *services, int count,
  cui_uptime_opts opts) =>
  cui_uptime_ex(u, id, services, count, &opts);

/** Calls `cui_time_histogram_ex`. */
inline cui_time_histogram_result Ui.time_histogram(
  Ui u, String id, double start, double bucket_seconds, int buckets,
  const cui_histogram_series *series, int series_count, double &sel_start,
  double &sel_end, cui_time_histogram_opts opts) =>
  cui_time_histogram_ex(
    u, id, start, bucket_seconds, buckets, series, series_count, &sel_start,
    &sel_end, &opts);

/** Calls `cui_coverage_ex`. */
inline cui_coverage_result Ui.coverage(
  Ui u, String id, const cui_coverage_file *files, int count,
  cui_coverage_opts opts) =>
  cui_coverage_ex(u, id, files, count, &opts);

/** Calls `cui_blame_ex`. */
inline cui_blame_result Ui.blame(
  Ui u, String id, List lines, const int *line_commit, int line_count,
  const cui_blame_commit *commits, int commit_count, cui_blame_opts opts) =>
  cui_blame_ex(
    u, id, lines.c_strings(), line_commit, line_count, commits, commit_count,
    &opts);

/** Calls `cui_feature_flags_ex`. */
inline cui_feature_flags_result Ui.feature_flags(
  Ui u, String id, cui_feature_flag *flags, int count, List envs,
  cui_feature_flags_opts opts) =>
  cui_feature_flags_ex(
    u, id, flags, count, envs.c_strings(), envs.len(), &opts);

/** Calls `cui_api_explorer_ex`. */
inline cui_api_explorer_result Ui.api_explorer(
  Ui u, String id, const cui_api_endpoint *endpoints, int count,
  cui_api_explorer_opts opts) =>
  cui_api_explorer_ex(u, id, endpoints, count, &opts);

/** Calls `cui_draw_polyline`. */
inline void Ui.draw_polyline(
  Ui u, const cui_vec2 *points, int count, float thickness, cui_color color,
  bool closed) =>
  cui_draw_polyline(u, points, count, thickness, color, closed);

/** Calls `cui_draw_polygon`. */
inline void Ui.draw_polygon(
  Ui u, const cui_vec2 *points, int count, cui_color color) =>
  cui_draw_polygon(u, points, count, color);

/* gen-arrays: end generated methods */

/* The method forms of the methods above that take an option record. */

/* gen-arrays: begin generated forms */

expand %(
  prop_vec2 prop_vec3 prop_vec4 tree_begin tree_cell donut_chart
  sparkline otp_input reorder_begin (line_chart 1) (bar_chart 1)
  each_begin each_end item_begin table_row_begin cell_text grid_cell_text
  (tour 1) toggle_group (reactions 1) (speed_dial 1)
  (swipe_item_begin 1 3) (filter_bar 1) (tree_table_begin 1 3)
  diff_view_rows (presence 1) (ticker 1) heatmap (calendar_heatmap 2)
  (treemap 1) (radar_chart 1) (funnel 1) (sankey 2) (waffle 1)
  (split_bar 1) (bar_list 1) (activity_rings 1) (scatter_chart 1)
  (candlestick 1) (tab_bar 1) (waveform 1) (agent_plan 1) (source_list 1)
  (prompt_suggestions 1) (model_picker 1) (week_calendar 2)
  (month_calendar 2) (gantt 1) (toc 1) (checklist 1) multi_select
  (histogram_slider 1) (level_meter 1) (doc_tabs 1) (prop_vec 1)
  (hex_view 1) (flame_graph 1) curve_editor gradient_editor
  (timeline_editor 1) kv_editor (problems 1) (pipeline 2)
  (query_builder 1) (keymap 1) (commit_graph 1) (graph_view 1 3)
  (waterfall 1) (trace_view 1 3) (test_explorer 1) (stack_trace 1)
  (uptime 1) (time_histogram 4) (coverage 1) (blame 4) (feature_flags 1)
  (api_explorer 1) (draw_polyline 0) (draw_polygon 0))
macro Unit(Name $method, Literal @pairs) {
  @x2cui_form($method, $pairs)
}
/* gen-arrays: end generated forms */
