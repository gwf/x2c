/*  rendering.x -- List rendering operations */


/* rendering

   A List renders flat when it fits in the rest of the line. Otherwise its
   elements follow one another, and each starts a new line when the current
   line is full or has run more than 40 columns past its indentation. */

static const int _WIDTH = 80;

/* One rendering: the output Buffer and whether elements write their `str`
   or their `repr`. */
static typedef struct Render {
  Buffer out;
  Symbol mode;
} Render;

/** Returns the human-readable rendering of `lst`.
    Elements are rendered with their own `str`, so a `String` element appears
    unquoted. The writer pads inside parentheses and breaks nested structure
    across lines at about 80 columns. Nil renders as `()`. The canonical
    result follows the active `String` pool chain, may already be owned by an
    ancestor, and remains live until its owning pool is released. Use
    `List.repr` when the text has to read back in.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
String List.str(List lst) {
  Buffer buf = $auto(Buffer.new(0));
  lst.write_str(buf);
  return buf;
}

/** Appends the `List` display text to `out`, using each element's `write_str`.
    `List.str` calls this to build its result. The display form has one space
    inside each parenthesis, as in `( a b )`, including when nested in another
    container. This method temporarily sets the destination `Buffer`'s padding
    to one and restores it afterward.
*/
Buffer List.write_str(List lst, Buffer out) {
  Render r = {out, <str>};
  $let(out.padding, 1) _value(r, lst);
  return out;
}

/** Returns the re-readable rendering of `lst`.
    This is the `%(...)` spelling of the same data. Elements are rendered with
    their own `repr`, so `String`s come back quoted and `Atom`s print as bare
    names, and `nil` renders as `()`. Long nested structure wraps at about 80
    columns. The canonical result follows the active `String` pool chain, may
    already be owned by an ancestor, and remains live until that owner is
    released.
    Raises: `<alloc-fail>` or `<size-limit>` while constructing the result.
*/
String List.repr(List lst) {
  Buffer buf = $auto(Buffer.new(0));
  lst.write_repr(buf);
  return buf;
}

/** Appends the readable representation of `List` to a `Buffer`. */
Buffer List.write_repr(List lst, Buffer out) {
  Render r = {out, <repr>};
  _value(r, lst);
  return out;
}

/* Renders `elem` at the current column, breaking lines as it goes. */
static void _value(Render &r, Var elem) {
  Buffer out = r.out;
  if (out.pos >= _WIDTH - 1 || out.pos - out._indent > 40)
    out.newline_indent();
  if (elem is not <list>) _leaf(r, elem);
  else if (!elem.list()) _nil(out);
  else if (!_fits(r, elem)) _items(r, elem);
}

/* A leaf that overflows the line is written again on the next one. */
static void _leaf(Render &r, Var elem) {
  Buffer out = r.out;
  size_t before = out.content.length, position = out.pos;
  _write_leaf(r, elem);
  size_t length = out.content.length - before;
  if (position + length <= _WIDTH) return;
  out.unwrite(length);
  out.newline_indent();
  _write_leaf(r, elem);
}

static void _nil(Buffer out) {
  if (out.pos + 2 > _WIDTH) out.newline_indent();
  out.write("()");
}

/* Writes a List flat when it fits in the rest of the line. Returns zero,
   having written nothing, when it does not fit. */
static int _fits(Render &r, Var elem) {
  Buffer line = $auto(Buffer.new(r.out.padding));
  Render flat = {line, r.mode};
  _flat(flat, elem);
  if (r.out.pos + line.content.length > _WIDTH) return 0;
  r.out.write_len(line.content.bytes, line.content.length);
  return 1;
}

/* Writes a List's elements in turn, each rendered as `_value`
   does. Cells are immutable, so a chain cannot reach itself; a cycle through
   a mutable container in a car stops at that container's own guard. */
static void _items(Render &r, Var elem) {
  List lst = elem;
  Buffer out = r.out;
  if (out.pos - out.tabstop() > 5) out.newline_indent();
  _open(lst, out);
  for (List l = lst; l; l = l.cdr()) {
    _value(r, l.car());
    if (l.cdr()) out.write(" ");
  }
  _close(out);
}

/* Writes `elem` on one line. */
static void _flat(Render &r, Var elem) {
  if (elem is not <list>) _write_leaf(r, elem);
  else if (!elem.list()) r.out.write("()");
  else _flat_items(r, elem);
}

static void _flat_items(Render &r, Var elem) {
  List lst = elem;
  Buffer out = r.out;
  _open(lst, out);
  for (List l = lst; l; l = l.cdr()) {
    _flat(r, l.car());
    if (l.cdr()) out.write(" ");
  }
  _close(out);
}

static void _write_leaf(Render &r, Var elem) {
  if (r.mode == <str>) elem.write_str(r.out);
  else if (elem is <symbol>) Atom.write_repr(elem, r.out);
  else elem.write_repr(r.out);
}

/* Opens a List and makes the column after its padding the tabstop. */
static void _open(List lst, Buffer out) {
  out.write("(");
  if (lst.car() is not <list>) out.pad();
  out.push();
}

static void _close(Buffer out) {
  if (out[-1] != ')') out.pad();
  out.write(")");
  out.pop();
}
