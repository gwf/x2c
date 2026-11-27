/*  builder.x -- edit a UI held as a List by pointing at it

    The window draws a tree with a `View`, as a finished program would,
    between a palette of components and an inspector. In edit mode a
    click selects the component under the pointer instead of pressing it:
    the palette, grouped and searched, adds a component after the
    selection or inside a selected block, or where a drag of its name is
    released. The inspector edits the selection's arguments and options,
    and the toolbar moves or deletes it. Dragging a component moves it to
    the line shown, among its siblings or into another block. The inspector
    groups the options, sets a block's spacing and alignment, and
    gives sizes as Auto, Fit, Fill, or Fixed. A selected block also has
    a handle in each side's padding and in each gap, which a drag sets.
    An outline under the palette lists every node, and a click on a line
    selects its node. A right
    click on the tree or the outline, or a key, selects around the
    selection, wraps it in a row or column, unwraps a block, duplicates,
    moves, and deletes; `keys` lists them. The inspector's Events group
    makes a component send a message or call a procedure, and makes a
    block handle the messages sent inside it. In run mode the tree
    behaves as it will in a program, and the inspector's place shows each
    handler run and a box that evaluates Lisp. The tree uses CUI's own
    layout, so a component's place is its position among its siblings.

    Usage:
      builder [FILE]             edit FILE, a tree written as one datum
      builder --check IMAGE.png  select, add, and run off screen

    A file `FILE.lisp` beside FILE, when there is one, is evaluated first
    and defines what the tree's handlers call. A procedure the tree calls
    and the file lacks gets a stub there when the tree runs or is saved.

    This file holds the shared types and the frame; the module block
    below splices the rest into one unit: notebook.x for the tree opened
    when no file is given, document.x for the tree and its
    edits, canvas.x for the pointer over the tree, panes.x for the
    toolbar, outline, and palette, inspector.x and events.x for the
    inspector, and check.x for `--check`.
*/
import "x2cui" with App, Offscreen, TextField, Ui, View, ViewLisp;

#include "datum.x"
#include "path.x"
#include <stdio.h>
#include <string.h>

enum {
  DEPTH = 32, DRAWN = 2048, FIELDS = 64, LISTED = 64, OFFERED = 64,
  SPACERS = 36, UNDO = 200
};

// How near a block's edge a drop goes beside the block, not into it.
module const float EDGE = 6;
// The side of the square handle at the selection's corner.
module const float HANDLE = 10;
// The width of the inspector's labels.
module const float LABEL = 96;

// Where a node is: the position of each node on the way from the root.
typedef struct Where { int depth; int at[DEPTH]; } Where;

/* A node the view drew this frame, the id CUI gave its component, and
   where the node is. Equal Lists are one List, so two equal nodes are
   told apart only by where they are. */
typedef struct Drawn { List node; cui_id id; Where where; } Drawn;

/* A handle on a selected block that sets its spacing by a drag: where
   it is, the option it sets and that option's value when drawn, the axis
   it moves along (0 for x), and the points of the option one point of
   movement makes. */
typedef struct Spacer {
  cui_rect at;
  String option;
  float value;
  int axis;
  float scale;
} Spacer;

// What a key or a menu item asks of the selection.
typedef enum Command {
  NOTHING, TO_PARENT, TO_CHILD, TO_PREVIOUS, TO_NEXT, MOVE_UP, MOVE_DOWN,
  WRAP_ROW, WRAP_COLUMN, UNWRAP, DUPLICATE, DELETE, UNDO_LAST, REDO_LAST
} Command;

// The inspector's groups of options.
enum { CONTENT, LAYOUT, SIZE, STYLE, EVENTS, BEHAVIOR, OTHER, GROUPS };

#ifdef __APPLE__
#define PRIMARY "Cmd "
#else
#define PRIMARY "Ctrl "
#endif

/* A command's key, and for one the menu offers, its label and the key as
   the menu shows it. */
typedef struct Key {
  Command command;
  int mods;
  cui_key key;
  char *label, *shown;
} Key;

module Key keys[] = {
  { WRAP_ROW, CUI_MOD_SHIFT, CUI_KEY_R, "Wrap in row", "Shift R" },
  { WRAP_COLUMN, CUI_MOD_SHIFT, CUI_KEY_C, "Wrap in column", "Shift C" },
  { UNWRAP, CUI_MOD_SHIFT, CUI_KEY_U, "Unwrap", "Shift U" },
  { DUPLICATE, CUI_MOD_PRIMARY, CUI_KEY_D, "Duplicate", PRIMARY "D" },
  { MOVE_UP, CUI_MOD_ALT, CUI_KEY_UP, "Move earlier", "Alt Up" },
  { MOVE_DOWN, CUI_MOD_ALT, CUI_KEY_DOWN, "Move later", "Alt Down" },
  { TO_PARENT, 0, CUI_KEY_LEFT, "Select parent", "Left" },
  { TO_CHILD, 0, CUI_KEY_RIGHT, "Select first child", "Right" },
  { DELETE, 0, CUI_KEY_DELETE, "Delete", "Delete" },
  { DELETE, 0, CUI_KEY_BACKSPACE },
  { TO_PREVIOUS, 0, CUI_KEY_UP },
  { TO_NEXT, 0, CUI_KEY_DOWN },
  { UNDO_LAST, CUI_MOD_PRIMARY, CUI_KEY_Z },
  { REDO_LAST, CUI_MOD_PRIMARY | CUI_MOD_SHIFT, CUI_KEY_Z },
};

typedef struct Builder {
  Lisp lisp;
  View view;
  List tree;
  // Trees before each change, and trees an undo went back from.
  Array undo, redo;
  String file, status;
  bool editing, selected;
  Where where;
  // What the view drew last frame, for hit tests and the outline.
  Drawn drawn[DRAWN];
  int drawn_count;
  // The pointer as the input hook saw it, and a click it kept.
  cui_id canvas_id;
  cui_rect canvas;
  cui_vec2 pointer;
  bool clicked;
  /* A press held on the tree, where it began, whether the pointer has
     moved far enough to be dragging, and a drag just released. */
  bool pressed, dragging, dropped;
  cui_vec2 press;
  // Where a drop would put the selection: a block, a position, a line.
  bool aimed;
  Where target;
  cui_id target_id;
  int target_index;
  cui_rect line;
  /* The selection's rectangle, the handle at its corner, and a press
     that began on the handle and so sizes the selection. */
  cui_rect chosen, handle;
  bool sizing, sized;
  /* The selected block's spacing handles; the one a press holds, as its
     number plus one, with where the press began; and whether its drag
     has changed the tree, which is one step of undo. */
  Spacer spacers[SPACERS], held;
  int spacer_count, holding;
  cui_vec2 held_from;
  bool held_changed;
  // The inspector's text, reloaded from the node when `refill` is set.
  TextField fields[FIELDS];
  bool refill;
  int bound, slot;
  /* The field an edit of the inspector came from, while that field keeps
     the keyboard or the pointer; its edits are one step of undo. */
  String visiting;
  // Open groups, whether every option shows, and the text that finds one.
  bool open[GROUPS], open_around, all;
  TextField search;
  // What a key or a menu item asked for, done when the next frame starts.
  Command command;
  // Whether a menu was open last frame, and whether one is open in this.
  bool menu_open, menu_shown;
  /* The outline's area, each line and where its node is, and a press on
     a line, kept by the input hook as the line's number plus one. */
  cui_id outline_id;
  cui_rect outline_area, listed[LISTED];
  Where listed_where[LISTED];
  int lines, picked;
  /* The palette's search, its area, and each name it offers. A press on
     a name is `carry`, the name's number plus one; once the pointer moves
     it is `carrying` a new component, and `placed` when released. */
  TextField find;
  cui_id palette_id;
  cui_rect palette_area, offered[OFFERED];
  String offered_name[OFFERED];
  int offered_count, carry;
  bool carrying, placed;
  /* The text of the tree's `FILE.lisp`, which Save writes; the run log;
     and the message box, whose Lisp the session evaluates. */
  String program;
  Array log;
  TextField message;
  // Where the check finds the builder's own controls.
  cui_rect mode_button, add_button, first_field, all_switch, find_field;
  cui_rect message_field;
  Map located;
} Builder;

module String sample = %"
  (column ((pad 24) (gap 12))
    (heading () \"A tiny counter\" 2)
    (button ((variant primary) (on-click bump)) \"Add one\")
    (text () (eval (ui-text \"Clicked \" clicks \" times.\"))))";

module String sample_program = %"
  (def clicks 0)
  (def bump (lambda () (def clicks (+ clicks 1))))";

// The rest of the builder, in the order its types are needed.
module {
  "notebook.x",
  "document.x",
  "canvas.x",
  "panes.x",
  "inspector.x",
  "events.x",
  "check.x",
}

module void draw(Ui ui, Builder &b) {
  // Rectangles are read before this frame submits anything: they are the
  // last frame's layout, which is what the pointer was aimed at.
  b.canvas = ui.get_rect(b.canvas_id);
  b.outline_area = ui.get_rect(b.outline_id);
  b.palette_area = ui.get_rect(b.palette_id);
  if (b.clicked) select_under(b, ui);
  b.clicked = false;
  if (!b.pressed || b.sizing)
    b.chosen = b.selected ? drawn_at(b, ui, b.where) : (cui_rect){ 0 };
  else if (!b.dragging && b.selected) b.chosen = drawn_at(b, ui, b.where);
  b.handle = (cui_rect){ b.chosen.x + b.chosen.w - HANDLE,
                         b.chosen.y + b.chosen.h - HANDLE, 2 * HANDLE,
                         2 * HANDLE };
  if (b.chosen.w <= 0) b.handle = (cui_rect){ 0 };
  if (b.holding && b.selected) drag_spacer(b);
  place_spacers(b, ui);
  b.aimed = false;
  bool over = within(b.canvas, b.pointer);
  if ((b.dragging || b.dropped) && b.selected && b.where.depth ||
      (b.carrying || b.placed) && over)
    aim(b, ui);
  if (b.dropped && b.aimed) drop(b);
  if (b.placed && b.aimed)
    put(b, b.target, b.target_index,
        fresh(b, b.offered_name[b.carry - 1]));
  if (b.placed) b.carry = 0;
  if (b.sized && b.selected) resize(b);
  b.dropped = b.sized = b.placed = false;
  if (b.picked) select_at(b, b.listed_where[b.picked - 1]);
  b.picked = 0;
  if (!ui.wants_keyboard() && !ui.mouse_down(CUI_MOUSE_LEFT))
    b.visiting = NULL;
  b.menu_open = b.menu_shown;
  b.menu_shown = false;
  keyed(ui, b);
  run(b, b.command);
  b.command = NOTHING;
  ui.column (width: fill, height: fill) {
    toolbar(ui, b);
    ui.separator();
    ui.row (width: fill, height: fill) {
      // The palette takes three fifths of the height, the outline two.
      ui.column (width: 220, height: fill) {
        ui.column (width: fill, height: CUI_GROW(3)) palette(ui, b);
        ui.separator();
        ui.column (width: fill, height: CUI_GROW(2)) outline_pane(ui, b);
      }
      canvas(ui, b);
      inspector(ui, b);
    }
  }
}

/* Opens `file`, or with no file the tree `start` and its program
   `start_program`, saved as builder.tree. */
module void open_file(Builder &b, Ui ui, String file, String start,
                      String start_program) {
  b.lisp = Lisp.new();
  ViewLisp.install(b.lisp);
  b.file = file ? file : "builder.tree";
  Path saved = b.file, program = %"$(b.file).lisp";
  String text = file && saved.exists() ? saved.read_text() : start;
  b.program = program.exists() ? program.read_text()
            : !file ? start_program : "";
  b.lisp.eval_string(b.program);
  Var tree = void;
  if (!read_value(text, tree) || !is_node(tree))
    raise %(bad-arg (operation "builder") (path $(b.file))
            (reason "the file is not one tree"));
  b.tree = tree;
  b.undo = [];
  b.redo = [];
  b.located = {};
  for (int i = 0; i < GROUPS; i++) b.open[i] = true;
  b.open_around = true;
  b.search = TextField.new(64);
  b.find = TextField.new(64);
  b.message = TextField.new(256);
  b.log = [];
  b.view = View.new(b.lisp, "ui");
  b.view.set(b.tree);
  b.view.trace(logged, &b);
  b.editing = true;
  for (int i = 0; i < FIELDS; i++) b.fields[i] = TextField.new(512);
  ui.set_input_hook(capture, &b);
}

int main(int argc, char **argv) {
  if (argc == 3 && !strcmp(argv[1], "--check")) return check(argv[2]);
  static Builder b;
  // Wide enough that a window such as the notebook fits on the canvas.
  App app = auto App.open(title: "Builder", width: 1640, height: 980);
  open_file(b, app.ui(), argc > 1 ? argv[1] : NULL, notebook,
            notebook_program);
  while (app.frame()) draw(app.ui(), b);
  return 0;
}
