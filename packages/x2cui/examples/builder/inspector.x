/*  inspector.x -- the selection's arguments and options, by group

    The rows come from the component table and `shown`, which gives an
    option a group, whether it is common, a step, and a line of help.
*/

/* How the inspector shows an option: its group, whether it shows before
   "All options", the step of a number, and a line of help. An option
   with no row is in Other and shows under "All options" or once set. */
static typedef struct Shown {
  char *name, *group;
  bool common;
  float step;
  char *help;
} Shown;

static Shown shown[] = {
  { "gap", "Layout", true, 1, "Space between the children" },
  { "pad", "Layout", true, 1, "Space inside the edge" },
  { "wrap", "Layout", false, 0, "Start a new line when the row is full" },
  { "columns", "Layout", false, 1, "The columns of a grid" },
  { "pad_x", "Layout", false, 1, "Space inside the left and right edges" },
  { "pad_y", "Layout", false, 1, "Space inside the top and bottom edges" },
  { "width", "Size", true, 1, "Fit the content, fill the space, or fixed" },
  { "height", "Size", true, 1, "Fit the content, fill the space, or fixed" },
  { "min_width", "Size", false, 1, "The least width" },
  { "max_width", "Size", false, 1, "The greatest width" },
  { "min_height", "Size", false, 1, "The least height" },
  { "max_height", "Size", false, 1, "The greatest height" },
  { "variant", "Style", true, 0, "The look of the button" },
  { "size", "Style", true, 1, "How large it is" },
  { "tone", "Style", true, 0, "Its color, by what it means" },
  { "color", "Style", false, 0, "The color of its text or mark" },
  { "bg", "Style", false, 0, "The background color" },
  { "border", "Style", false, 1, "The width of the border" },
  { "border_color", "Style", false, 0, "The color of the border" },
  { "radius", "Style", false, 1, "How round the corners are" },
  { "elevation", "Style", false, 0, "How far its shadow falls" },
  { "label", "Content", true, 0, "The text beside the control" },
  { "placeholder", "Content", true, 0, "The text shown while it is empty" },
  { "description", "Content", false, 0, "A second line under the label" },
  { "on_click", "Events", true, 0, "What a press does" },
  { "on_change", "Events", true, 0, "What a change does" },
  { "disabled", "Behavior", true, 0, "Ignore the pointer and the keys" },
  { "bind", "Behavior", false, 0, "The Lisp global the control edits" },
  { "id", "Behavior", false, 0, "A name that keeps the node's state" },
  { "show", "Behavior", true, 0, "The id of the card to show" },
};

static char *group_names[] = {
  "Content", "Layout", "Size", "Style", "Events", "Behavior", "Other"
};

// The view's own options, which no component's record lists.
static List own_options = %(("on_click" "form") ("on_change" "form")
                            ("bind" "form") ("id" "text"));

// Options a block's Layout group draws with controls of their own.
static bool laid_out(String name) =>
  name in %("dir" "gap" "pad" "align" "justify");

// A label beside a control, like the label of an inspector row.
module void row_label(Ui ui, String text) =>
  ui.text(text, width: LABEL,
          color: cui_color_of(ui, CUI_COLOR_TEXT_SECONDARY));

static Shown *shown_row(String name) {
  for (int i = 0; i < (int) (sizeof shown / sizeof shown[0]); i++)
    if (!strcmp(name, shown[i].name)) return &shown[i];
  return NULL;
}

static int group_of(String name) {
  Shown *row = shown_row(name);
  for (int i = 0; row && i < OTHER; i++)
    if (!strcmp(row.group, group_names[i])) return i;
  return OTHER;
}

/* What the inspector draws: a node, where it is, and the node it asks
   for, set when the frame's controls change the node. */
module typedef struct Inspecting {
  Where where;
  List node, edited;
  // What was changed, which names one step of undo.
  String field;
  // Whether the rows edit the block around the selection.
  bool around;
} Inspecting;

module List current(Inspecting &in) => in.edited ? in.edited : in.node;

module void set_option(Inspecting &in, String name, Var value) {
  in.edited = with_option(current(in), name, value);
  in.field = name;
}

// The option value `name` when `on`, and otherwise void, the default.
static Var unless_default(bool on, String name) =>
  on ? (Var) Atom.intern(name) : void;

// `name` as an option value, or none when it is the default `usual`.
static Var unless_usual(String name, String usual) =>
  unless_default(strcmp(name, usual) != 0, name);

static List renamed(List node, String name) =>
  %( $(Atom.intern(name)) @(node.cdr()) );

// Notes where a row is, for the check.
module void locate(Builder &b, Inspecting &in, String name, cui_rect r) {
  b.located[in.around ? %"around $name" : name] =
    %( $((double) r.x) $((double) r.y) $((double) r.w) $((double) r.h) );
}

module cui_rect located(Builder &b, String name) {
  List r = b.located[name];
  return r ? (cui_rect){ r[0].double(), r[1].double(), r[2].double(),
                         r[3].double() }
           : (cui_rect){ 0 };
}

/* One text field of the inspector, showing `value`. Returns true with
   `out` set when the text was changed to something that reads as a
   value: void for no text, the text itself for a `text` kind that does
   not start a form, and otherwise the form read. */
module bool typed(Ui ui, Builder &b, String label, String kind, Var value,
                  Var &out) {
  if (b.slot >= FIELDS) return false;
  TextField field = b.fields[b.slot++];
  if (b.refill) {
    field.buffer[0] = 0;
    if (!value.is_void())
      field.set(kind == "text" && value is <string> ? (String) value
                                                    : written(value));
  }
  Shown *row = shown_row(label);
  bool changed = ui.prop_text(label, field, tooltip: row ? row.help : NULL,
                              placeholder: kind == "text" ? "" : "Lisp");
  if (b.slot == 1) b.first_field = ui.last_rect();
  if (!changed) return false;
  out = void;
  if (field.empty()) return true;
  if (kind == "text" && field.buffer[0] != '(') {
    out = field.text();
    return true;
  }
  return read_value(field.text(), out);
}

module bool is_number(Var value) =>
  value.is_integer() || value.is_floating();

// Whether `value` is what a control for `kind` shows, not a Lisp form.
static bool plain(String kind, Var value) {
  if (value.is_void()) return true;
  if (kind == "number" || kind == "color" || kind == "bool")
    return is_number(value);
  if (kind == "size")
    return is_number(value) || value.is_atom() || value is <list>;
  return kind != "enum" || value.is_atom();
}

module int index_of(List members, Var value) {
  for (int i = 0; !value.is_void() && i < members.len(); i++)
    if (spelled(value) == (String) members[i]) return i;
  return -1;
}

static void enum_row(Ui ui, Inspecting &in, String what, List members,
                     Var now, String help) {
  int index = index_of(members, now) + 1;
  if (ui.prop_enum(what, %("default" @members), index, tooltip: help))
    set_option(in, what,
               index ? (Var) Atom.intern(members[index - 1]) : void);
}

static void number_row(Ui ui, Inspecting &in, String what, Var now,
                       Shown *row) {
  float value = now.is_void() ? 0 : now.double(), step = row ? row.step : 0;
  /* The row is unbounded, so CUI draws no range bar; a row with whole
     steps stays at zero or above. */
  if (ui.prop_float(what, value, step: step,
                    format: now.is_void() ? "default" : NULL,
                    tooltip: row ? row.help : NULL))
    set_option(in, what, step >= 1 ? whole(value > 0 ? value : 0)
                                    : (Var) (double) value);
}

static void color_row(Ui ui, Inspecting &in, String what, Var now,
                      String help) {
  cui_color color = now.is_void() ? (cui_color){ 0, 0, 0, 255 }
                                  : CUI_RGB(now.int());
  if (ui.prop_color(what, color, tooltip: help))
    set_option(in, what,
               (Var) (color.r << 16 | color.g << 8 | color.b));
}

/* A width or height as Auto, Fit, Fill, or Fixed, and for Fixed its
   points. Fixed starts at the size the node is drawn. */
static void size_row(Ui ui, Builder &b, Inspecting &in, String what,
                     Var now) {
  int index = now.is_void() ? 0 : is_number(now) ? 3
            : now is <list> || spelled(now) == "fill" ? 2 : 1;
  ui.row (width: fill, align: center, gap: 12) {
    row_label(ui, what);
    if (ui.segmented(%"size-$what", %("Auto" "Fit" "Fill" "Fixed"), index,
                     size: sm)) {
      cui_rect r = drawn_at(b, ui, in.where);
      float drawn = what == "width" ? r.w : r.h;
      Var sizes[] = { void, <fit>, <fill>, whole(drawn > 0 ? drawn : 100) };
      set_option(in, what, sizes[index]);
    }
    locate(b, in, what, ui.last_rect());
  }
  if (index != 3) return;
  float points = now.double();
  if (ui.prop_float(%"$what points", points, step: 1, suffix: "pt"))
    set_option(in, what, whole(points > 1 ? points : 1));
}

/* The editor for one option of the node, by its kind. A value that is a
   Lisp form, not the kind's own value, is edited as text. */
static void editor(Ui ui, Builder &b, Inspecting &in, List described,
                   Var now) {
  String what = described[0], kind = described[1];
  Shown *row = shown_row(what);
  String help = row ? row.help : NULL;
  if (!plain(kind, now)) kind = "form";
  if (kind == "size") return size_row(ui, b, in, what, now);
  if (kind == "enum")
    enum_row(ui, in, what, described.cdr().cdr(), now, help);
  else if (kind == "number") number_row(ui, in, what, now, row);
  else if (kind == "color") color_row(ui, in, what, now, help);
  else if (kind == "bool") {
    bool on = !now.is_void() && now.double() != 0;
    if (ui.prop_bool(what, on, tooltip: help))
      set_option(in, what, on ? (Var) 1 : void);
  }
  else {
    Var value = void;
    if (typed(ui, b, what, kind, now, value)) set_option(in, what, value);
  }
  locate(b, in, what, ui.last_rect());
}

/* One option's row: its editor, and when the option is set, a button
   that removes it, so the node goes back to the component's default. */
static void option_row(Ui ui, Builder &b, Inspecting &in, List described) {
  String what = described[0];
  Var now = option(current(in), what);
  cui_push_id(ui, what);
  defer cui_pop_id(ui);
  ui.row (width: fill, align: center, gap: 4) {
    ui.column (width: fill, gap: 4) editor(ui, b, in, described, now);
    if (now.is_void()) ui.gap(28);
    else if (ui.icon_button(CUI_ICON_X, variant: ghost, size: sm, width: 28,
                            tooltip: "Reset to the default")) {
      set_option(in, what, void);
    }
    if (!now.is_void()) locate(b, in, %"reset $what", ui.last_rect());
  }
}

/* The options the component of `node` has, and the view's own, which a
   record may list too. */
static List options_of(List node) {
  List row = component(spelled(node[0]));
  if (!row) return own_options;
  Array options = [];
  foreach (List described in (List) row[3]) options.push(described);
  foreach (List own in own_options) {
    List listed = ((List) row[3]).find(%!(List d) => d[0] == own[0]);
    if (!listed) options.push(own);
  }
  return options.list_free();
}

static List described(List node, String name) =>
  options_of(node).find(%!(List row) => row[0] == name);

/* Column or row. A `row` or `column` becomes the other; a block of
   another kind gets the option `dir`. */
static void direction(Ui ui, Builder &b, Inspecting &in) {
  List node = current(in);
  int index = is_row(node);
  ui.row (width: fill, align: center, gap: 12) {
    row_label(ui, "direction");
    if (ui.segmented("direction", %("Column" "Row"), index, size: sm,
                     full_width: true)) {
      String name = spelled(node[0]);
      if (name == "row" || name == "column") {
        in.edited = renamed(with_option(node, "dir", void),
                            index ? "row" : "column");
        in.field = "dir";
      }
      else set_option(in, "dir", unless_default(index, "row"));
    }
    locate(b, in, "direction", ui.last_rect());
  }
}

/* Where the children sit, as a 3 by 3 grid: along the block by
   `justify` and across it by `align`. Two switches give the spacing
   CUI has besides: space between the children, and children stretched
   across the block. The grid shows CUI's defaults for an unset option:
   children at the start, centred across a row, stretched across a
   column. A stretch lights the whole line across the block, and space
   between the whole line along it. */
static void alignment(Ui ui, Builder &b, Inspecting &in) {
  List node = current(in), places = %("start" "center" "end");
  bool row = is_row(node);
  String usual = row ? "center" : "stretch";
  Var align = option(node, "align"), justify = option(node, "justify");
  String across_is = align.is_void() ? usual : spelled(align);
  String along_is = justify.is_void() ? "start" : spelled(justify);
  bool stretch = strcmp(across_is, "stretch") == 0;
  bool between = strcmp(along_is, "between") == 0;
  int across = index_of(places, Atom.intern(across_is));
  int along = index_of(places, Atom.intern(along_is));
  ui.row (width: fill, gap: 12, align: center) {
    row_label(ui, "align");
    ui.column (gap: 2) {
      for (int y = 0; y < 3; y++)
        ui.row (gap: 2) {
          for (int x = 0; x < 3; x++) {
            int on_along = row ? x : y, on_across = row ? y : x;
            cui_push_id_int(ui, y * 3 + x);
            bool here = (between || on_along == along)
                     && (stretch || on_across == across);
            if (ui.button(" ", size: sm, width: 22,
                          variant: here ? CUI_BUTTON_PRIMARY
                                        : CUI_BUTTON_SECONDARY)) {
              set_option(in, "justify",
                         unless_default(on_along, places[on_along]));
              set_option(in, "align",
                         unless_usual(places[on_across], usual));
            }
            locate(b, in, %"cell $x $y", ui.last_rect());
            cui_pop_id(ui);
          }
        }
    }
    ui.column (gap: 4) {
      if (ui.switch("Space between", between))
        set_option(in, "justify", unless_default(between, "between"));
      if (ui.switch("Stretch", stretch))
        set_option(in, "align",
                   unless_usual(stretch ? "stretch" : row ? "center"
                                                          : "start",
                                usual));
    }
  }
}

// A block's spacing: direction, gap, padding, and where children sit.
static void block_layout(Ui ui, Builder &b, Inspecting &in) {
  List node = current(in);
  if (described(node, "dir")) direction(ui, b, in);
  foreach (String name in %("gap" "pad")) {
    List row = described(node, name);
    if (row) option_row(ui, b, in, row);
  }
  if (described(node, "align") && described(node, "justify"))
    alignment(ui, b, in);
}

/* Whether the inspector shows the option `name` of `node` now. A block
   reports no event, so its handlers are not common. */
static bool showing(Builder &b, List node, String name) {
  if (b.all)
    return b.search.empty() || strstr(name, b.search.text()) != NULL;
  Shown *row = shown_row(name);
  bool common = row && row.common &&
                !(is_block(node) && name.startswith("on_"));
  return common || !option(node, name).is_void();
}

// The rows of one group: each option the group holds that shows now.
static void group_rows(Ui ui, Builder &b, Inspecting &in, int group) {
  List node = current(in);
  bool block = is_block(node);
  foreach (List row in options_of(node)) {
    String name = row[0];
    if (group_of(name) != group || (block && laid_out(name))) continue;
    if (name == "show" && node[0] != <cards>) continue;
    if (showing(b, node, name)) option_row(ui, b, in, row);
  }
}

// Whether a group has a row to show.
static bool group_shows(Builder &b, List node, int group) {
  foreach (List row in options_of(node)) {
    String name = row[0];
    if (group_of(name) == group && !(is_block(node) && laid_out(name)) &&
        (name != "show" || node[0] == <cards>) && showing(b, node, name))
      return true;
  }
  return false;
}

// The node's arguments, as text or numbers, in the Content group.
static void arguments(Ui ui, Builder &b, Inspecting &in) {
  List node = in.node, row = component(spelled(node[0]));
  int at = 2;
  foreach (List argument in row ? (List) row[2] : %()) {
    String kind = argument[1], what = argument[0];
    if (kind == "bound" || kind == "field") continue;
    if (at >= node.len()) break;
    Var value = void;
    if (kind == "number" && is_number(node[at])) {
      float number = node[at].double();
      if (ui.prop_float(what, number, step: 1)) {
        in.edited = with_argument(current(in), at, whole(number));
        in.field = what;
      }
    }
    else if (typed(ui, b, what, kind, node[at], value)) {
      in.edited = with_argument(current(in), at,
                                value.is_void() ? (Var) "" : value);
      in.field = what;
    }
    at++;
  }
}

/* Changes the tree for an inspector edit. The changes from one field,
   while it keeps the keyboard or the pointer, are one step of undo. */
static void change_field(Builder &b, Inspecting &in) {
  String key = %"$(in.field) $(in.around ? 1 : 0)";
  for (int i = 0; i < in.where.depth; i++) key = %"$key/$(in.where.at[i])";
  List tree = replaced(b.tree, in.where, 0, in.edited);
  if (b.visiting && b.visiting == key) {
    b.tree = tree;
    b.view.set(tree);
  }
  else change(b, tree);
  b.visiting = key;
}

/* Shows the selection's arguments; the spacing of the block it is in;
   its own spacing when it is a block; and its options by group. Only
   common and set options show until "All options" is on. */
/* The spacing of the block around the selection, as "In row" or "In
   column". The root has none. */
static void around_group(Ui ui, Builder &b, Inspecting &around) {
  if (!around.node) return;
  cui_push_id(ui, "around");
  if (ui.inspector_group(is_row(around.node) ? "In row" : "In column",
                         b.open_around))
    block_layout(ui, b, around);
  cui_pop_id(ui);
}

module void inspector(Ui ui, Builder &b) {
  if (!b.editing) return run_pane(ui, b);
  ui.scroll (id: "inspector", width: 400, height: fill, pad: 10, gap: 8) {
    if (!b.selected) {
      ui.muted("Click a component to select it.");
      return;
    }
    Inspecting own = { b.where, node_at(b.tree, b.where) }, around = { 0 };
    ui.row (width: fill, align: center) {
      ui.heading(spelled(own.node[0]), 4);
      ui.spacer();
      if (ui.switch("All options", b.all)) b.refill = true;
      b.all_switch = ui.last_rect();
    }
    if (b.all && ui.search("inspect-search", b.search, size: sm) &
                 CUI_CHANGED)
      b.refill = true;
    b.slot = 0;
    b.located = {};
    cui_inspector_opts layout = { .label_width = LABEL };
    if (ui.inspector_begin("inspect", layout)) {
      List row = component(spelled(own.node[0]));
      bool argued = row && ((List) row[2]).len();
      if ((argued || group_shows(b, own.node, CONTENT)) &&
          ui.inspector_group("Content", b.open[CONTENT])) {
        arguments(ui, b, own);
        group_rows(ui, b, own, CONTENT);
      }
      // What the node does comes next to what it shows.
      if (has_events(own.node) &&
          ui.inspector_group("Events", b.open[EVENTS]))
        events(ui, b, own);
      if (own.where.depth) {
        around.where = own.where;
        around.where.depth--;
        around.node = node_at(b.tree, around.where);
        around.around = true;
      }
      // A block's own spacing comes before the spacing of the one around.
      bool block = is_block(own.node);
      for (int group = LAYOUT; group < GROUPS; group++) {
        if (group == LAYOUT + block) around_group(ui, b, around);
        if (group == EVENTS) continue;
        bool laid = group == LAYOUT && block;
        if (!laid && !group_shows(b, own.node, group)) continue;
        if (!ui.inspector_group(group_names[group], b.open[group])) continue;
        if (laid) block_layout(ui, b, own);
        group_rows(ui, b, own, group);
      }
      ui.inspector_end();
    }
    if (own.edited) change_field(b, own);
    else if (around.edited) change_field(b, around);
    // Text the person is typing stays as typed.
    b.refill = (own.edited || around.edited) && !ui.wants_keyboard();
  }
}
