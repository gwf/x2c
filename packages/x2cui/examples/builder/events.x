/*  events.x -- what a press or a change does, and the run log

    The Events group wires a component to a message or a procedure and a
    block to the messages sent inside it. A procedure the session lacks
    gets a stub in FILE.lisp; in run mode the log shows each handler run.
*/

// Whether the session has a global `name`.
static bool defined(Builder &b, String name) {
  Var value = void;
  return b.lisp.try_get(name, value);
}

// Adds a line to the run log.
module void note(Builder &b, String line) => b.log.push(line);

/* The procedures a handler of `node` or a node inside it calls by name:
   an `on-click` or `on-change` that is a name, and an `(on name form)`
   whose form is one. */
static void called(List node, Array &names) {
  foreach (List row in (List) node[1]) {
    Var handler = row.len() == 3 && spelled(row[0]) == "on" ? row[2]
                : row.len() == 2 && spelled(row[0]).startswith("on_")
                  ? row[1] : void;
    if (handler.is_atom() && !(written(handler) in names))
      names.push(written(handler));
  }
  if (!is_block(node)) return;
  for (int i = 2; i < node.len(); i++)
    if (is_node(node[i])) called(node[i], names);
}

/* Gives each procedure the tree calls and the session lacks a stub in
   `FILE.lisp` that returns its own name, so a run shows it was called. */
module void add_stubs(Builder &b) {
  Array names = [];
  called(b.tree, names);
  foreach (String name in names) {
    if (defined(b, name)) continue;
    String stub = %"(def $name (lambda () '$name))\n";
    b.program = b.program + stub;
    b.lisp.eval_string(stub);
    note(b, %"Added a stub for $name to $(b.file).lisp");
  }
}

/* The handler option of the event `node` reports, `on_change` for a
   component that edits a value and `on_click` for another, or NULL when
   it reports none. */
static String event_of(List node) {
  List row = component(spelled(node[0]));
  if (!row || row.len() < 5 || !row[4].int()) return NULL;
  foreach (List argument in (List) row[2])
    if ((String) argument[1] == "bound" || (String) argument[1] == "field")
      return "on_change";
  return "on_click";
}

/* A name for what `node` does, from its first text: "Sign in" gives
   `sign-in`. A node with no text gives its component's name. */
static String suggested(List node) {
  if (node.len() < 3 || !(node[2] is <string>)) return spelled(node[0]);
  Array kept = [];
  bool gap = false;
  foreach (char c in (String) node[2]) {
    if (isalnum(c)) {
      if (gap && kept.len()) kept.push("-");
      kept.push(%"$((char) tolower(c))");
      gap = false;
    }
    else gap = true;
  }
  return kept.len() ? kept.join("") : spelled(node[0]);
}

// The procedures `FILE.lisp` defines as `(def name (lambda ...))`.
static List procedures(Builder &b) {
  Array names = [];
  unsigned cursor = 0;
  Var form = void;
  try {
    while (b.lisp.read(b.program, cursor, form) != <eof>)
      match (form) {
        case %(def ?name (lambda *body)): names.push(written(name));
      }
  }
  catch %(?cause *detail): b.status = "FILE.lisp does not read";
  return names.list_free();
}

/* How a handler is written: 0 for none, 1 for `(send name)`, 2 for a
   procedure's name, and 3 for another Lisp form. */
module int handler_mode(Var handler) {
  if (handler.is_void()) return 0;
  if (handler.is_atom()) return 2;
  match (handler) {
    case %(send ?name): return name.is_atom() ? 1 : 3;
  }
  return 3;
}

/* The row of the event option `what`: None, Send a message, or Call a
   procedure, with the message's or procedure's name. A procedure the
   session lacks gets a stub when the tree runs or is saved. */
static void event_row(Ui ui, Builder &b, Inspecting &in, String what) {
  List node = current(in);
  Var now = option(node, what);
  int mode = handler_mode(now), chosen = mode;
  String shown = what.replace("_", "-");
  cui_push_id(ui, what);
  defer cui_pop_id(ui);
  ui.row (width: fill, align: center, gap: 12) {
    row_label(ui, shown);
    List choices = mode == 3 ? %("None" "Send" "Call" "Lisp")
                             : %("None" "Send" "Call");
    if (ui.segmented("mode", choices, chosen, size: sm) && chosen != mode) {
      Atom name = Atom.intern(suggested(node));
      Var made[] = { void, %(send $name), name, now };
      set_option(in, what, made[chosen]);
      b.refill = true;
    }
    locate(b, in, %"$what mode", ui.last_rect());
  }
  Var value = void;
  if (mode == 1) {
    Var name = ((List) now)[1];
    if (typed(ui, b, "message", "text", name, value) && !value.is_void())
      set_option(in, what, %(send $(Atom.intern(value))));
    locate(b, in, %"$what message", ui.last_rect());
  }
  else if (mode == 2) {
    List known = procedures(b);
    int index = index_of(known, now) + 1;
    if (known.len() &&
        ui.prop_enum("procedure", %("choose" @known), index) && index) {
      set_option(in, what, Atom.intern(known[index - 1]));
      b.refill = true;
    }
    if (typed(ui, b, "name", "text", now, value) && !value.is_void())
      set_option(in, what, Atom.intern(value));
    locate(b, in, %"$what name", ui.last_rect());
    if (!defined(b, written(now)))
      ui.muted(%"Run or Save adds a stub for $(written(now)) to FILE.lisp.");
  }
  else if (mode == 3) {
    if (typed(ui, b, shown, "form", now, value)) set_option(in, what, value);
  }
}

// `node` with its handler of the message `name` set to `form`, or none.
static List with_handler(List node, Var name, Var form) {
  Array rows = [];
  bool placed = form.is_void();
  foreach (List row in (List) node[1]) {
    bool same = row.len() == 3 && spelled(row[0]) == "on" && row[1] == name;
    if (!same) rows.push(row);
    else if (!placed) {
      rows.push(%( on $name $form ));
      placed = true;
    }
  }
  if (!placed) rows.push(%( on $name $form ));
  return %( $(node[0]) $(rows.list_free()) @(node.cdr().cdr()) );
}

static void set_handler(Inspecting &in, Var name, Var form) {
  in.edited = with_handler(current(in), name, form);
  in.field = %"on $(written(name))";
}

// Whether `block` has an `(on name form)` option for the message `name`.
module bool handles(List block, Var name) {
  foreach (List row in (List) block[1])
    if (row.len() == 3 && spelled(row[0]) == "on" && row[1] == name)
      return true;
  return false;
}

/* The messages a handler in `node` or a node inside it sends, as names,
   that `block` does not handle. */
static void sent(List node, List block, Array &names) {
  foreach (List row in (List) node[1]) {
    if (row.len() != 2 || !spelled(row[0]).startswith("on_")) continue;
    match (row[1]) {
      case %(send ?name *rest): {
        if (!handles(block, name) && !(written(name) in names))
          names.push(written(name));
      }
    }
  }
  if (!is_block(node)) return;
  for (int i = 2; i < node.len(); i++)
    if (is_node(node[i])) sent(node[i], block, names);
}

/* A block's handlers: one row for each message it handles, whose
   handler body is edited as Lisp, and a Handle button for each message
   sent inside it that it does not handle yet. */
static void block_handlers(Ui ui, Builder &b, Inspecting &in) {
  List node = current(in);
  foreach (List row in (List) node[1]) {
    if (row.len() != 3 || spelled(row[0]) != "on") continue;
    String name = written(row[1]);
    Var form = row[2], body = form, value = void;
    bool simple = false;
    match (form) {
      case %(lambda () ?inner): { body = inner; simple = true; }
    }
    cui_push_id(ui, name);
    ui.row (width: fill, align: center, gap: 4) {
      ui.column (width: fill) {
        if (typed(ui, b, %"on $name", "form", body, value) &&
            !value.is_void())
          set_handler(in, row[1], simple ? %(lambda () $value) : value);
        locate(b, in, %"on $name", ui.last_rect());
      }
      if (ui.icon_button(CUI_ICON_X, variant: ghost, size: sm, width: 28,
                         tooltip: "Stop handling the message"))
        set_handler(in, row[1], void);
    }
    cui_pop_id(ui);
  }
  Array unhandled = [];
  for (int i = 2; i < node.len(); i++)
    if (is_node(node[i])) sent(node[i], node, unhandled);
  foreach (String name in unhandled) {
    cui_push_id(ui, %"handle $name");
    ui.row (width: fill, align: center, gap: 12) {
      row_label(ui, name);
      ui.muted("is sent inside");
      ui.spacer();
      if (ui.button("Handle", size: sm)) {
        Atom message = Atom.intern(name);
        set_handler(in, message, %(lambda () (quote $message)));
        b.refill = true;
      }
      locate(b, in, %"handle $name", ui.last_rect());
    }
    cui_pop_id(ui);
  }
}

// Whether the Events group has a row for `node`.
module bool has_events(List node) {
  if (event_of(node)) return true;
  if (!is_block(node)) return false;
  foreach (List row in (List) node[1])
    if (row.len() == 3 && spelled(row[0]) == "on") return true;
  Array unhandled = [];
  for (int i = 2; i < node.len(); i++)
    if (is_node(node[i])) sent(node[i], node, unhandled);
  return unhandled.len() > 0;
}

// The Events group: the node's event, or the messages a block handles.
module void events(Ui ui, Builder &b, Inspecting &in) {
  List node = current(in);
  String event = event_of(node);
  if (event) event_row(ui, b, in, event);
  foreach (String other in %("on_click" "on_change"))
    if (other != event && !option(node, other).is_void())
      event_row(ui, b, in, other);
  if (is_block(node)) block_handlers(ui, b, in);
}

/* In run mode the inspector's place shows the run log, newest first,
   and a message box whose Lisp the session evaluates on Return. */
module void run_pane(Ui ui, Builder &b) {
  ui.column (width: 400, height: fill, pad: 10, gap: 8) {
    ui.heading("Run", 4);
    ui.muted("Each handler run, the node it belongs to, and its result.");
    ui.row (width: fill) {
      int typed = ui.input("message-box", b.message,
                           placeholder: "Lisp, such as (bump)");
      b.message_field = ui.last_rect();
      if (typed & CUI_SUBMITTED && !b.message.empty()) {
        String text = b.message.text();
        try note(b, %"> $text: $(written(b.lisp.eval_string(text)))");
        catch %(?cause *detail):
          note(b, %"> $text: raised $(cause.repr()) $(detail.repr())");
        b.message.buffer[0] = 0;
      }
    }
    ui.scroll (id: "run-log", width: fill, height: fill, gap: 2) {
      int shown = 0;
      for (int i = b.log.len() - 1; i >= 0 && shown < 100; i--, shown++)
        ui.text((String) b.log[i], width: fill);
    }
  }
}

// Notes each handler the running tree runs in the run log.
module void logged(void *user, List node, Var event, Var result) {
  Builder *b = user;
  if (!node) return note(*b, %"$(written(event)): no block handles it");
  String line = %"$(listed(node)) $(written(event))";
  note(*b, result.is_void() ? line : %"$line: $(written(result))");
}
