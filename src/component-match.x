/*  component-match.x -- match statements

    A match lowers to C text around its subject, patterns, and bodies: a
    block that reads the subject once as a List and switches on the bits of
    its head. Lowering steps into the nodes the text holds, and the
    `switch` is the barrier the cleanup walk knows, so an arm's `break`
    leaves the match and `continue` reaches the enclosing loop. Each arm
    tests its pattern, declares its binders, runs its body, and breaks; an
    arm that fails falls into the next. A static pattern of literals,
    unique binders, typed captures, nested Lists, and a final `*` is tested
    in place by nested `if` tests on cursors over the subject. Any other
    pattern captures into a buffer: a macro-valued case through its macro,
    and the rest through the Match runtime, at a static site when the
    pattern's value is the same each time it runs.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"

// C text

/* Moves the C text written to `b` into `out`. */
meta static void _match_flush(Buffer b, Array out) {
  if (b.len()) {
    out.push(b.str());
    b.clear();
  }
}

/* Ends the C text written to `b` and places `node` after it in `out`. */
meta static void _match_place(Buffer b, Array out, Var node) {
  _match_flush(b, out);
  out.push(node);
}

/* The switch body's block items from `out`: each directive alone, and the
   text and nodes between directives as one item. */
meta static List _match_items(Array out) {
  Array items = [], run = [];
  foreach (Var piece, out) {
    match (piece) case %(preproc ?): {
      if (run.len()) items.push(cons(" ", run));
      run.clear();
      items.push(piece);
      continue;
    }
    run.push(piece);
  }
  if (run.len()) items.push(cons(" ", run));
  return items.list_free();
}

/* 1 for a directive that opens a conditional group, -1 for one that
   closes it, and 0 for any other. */
meta static int _match_nesting(String text) {
  String directive = text.strip(" \t").remove_prefix("#").strip(" \t");
  if (directive.startswith("endif")) return -1;
  return directive.startswith("if");
}

/* The cursor that walks the List `depth` levels into the subject. */
meta static String _match_cursor(int depth) =>
  depth ? %"_x2c_match_cursor$depth" : "_x2c_match_cursor";

// pattern values

/* The head Symbol of a pattern value whose first element is a literal
   Symbol, or 0. */
meta static Symbol _match_head(Var value) {
  if (value is not <list> || !value.list()) return 0;
  Var head = value.list().car();
  if (head is not <symbol> || head == <x2c-dyn> || head.is_binder() ||
      head.is_match_op())
    return 0;
  return head;
}

/* The arm's binders, the definite binders a Match of `value` captures, in
   their capture order. */
meta static List _match_binders(Var value) {
  MatchCaptureLayout layout = MatchCaptureLayout.analyze(value);
  List binders = layout.definite_list();
  layout.free();
  return binders;
}

/* The tag the typed capture `(!is ?name type <tag>)` tests, with its
   binder in `binder`, or 0. The runtime canonicalizes `varray` and
   `vmap`, so those keep the Match call. */
meta static Symbol _match_capture_tag(Var element, Var &binder) {
  match (element)
    case %((!quote !is) ?name type ?(Symbol tag)):
      if (tag != <x2c-dyn> && tag != <varray> && tag != <vmap>) {
        binder = name;
        return tag;
      }
  return 0;
}

// nested tests

/* Starts the next test of the condition the arm has open, or opens one
   after a binder's declaration closed it. */
meta static void _match_and(Buffer b, int &testing) {
  b.write(testing ? " && " : " if (");
  testing = 1;
}

/* Declares `binder` from `cell`, a `List` for a `*name` binder, after the
   open condition, whose brace `braces` counts. */
meta static void _match_bind(
  Buffer b, Var binder, String cell, int &testing, int &braces) {
  if (testing) {
    b.write(") {");
    braces++;
    testing = 0;
  }
  String type = binder.is_list_binder() ? "List" : "Var";
  String name = binder.str()[1:];
  b.printf(" %s %s = %s;", type, name, cell);
}

/* Writes the tests of the element `part` of a static pattern, read from
   `cell`, and returns 0 when they are complete, 1 for a nested List the
   caller walks next, 2 for a literal the caller compares with the
   pattern's own cell, or -1 outside the form the arm can test in place:
   an operator, a computed part, or a repeated binder. */
meta static int _match_element(
  Buffer b, Var part, String cell, Array seen, int &testing, int &braces) {
  Var binder = part;
  Symbol tag = part is <list> ? _match_capture_tag(part, binder) : 0;
  if (tag) {
    _match_and(b, testing);
    b.printf("Var_is(%s, %lu)", cell, (unsigned long) tag);
    part = binder;
  }
  if (part == <?>) return 0;
  if (part.is_atom_binder() && !(part in seen)) {
    seen.push(part);
    _match_bind(b, part, cell, testing, braces);
    return 0;
  }
  List list = part is <list> ? part.list() : NULL;
  if (part.is_binder() || part.is_match_op() || part == <x2c-dyn> ||
      (list && list.car().is_match_op()))
    return -1;
  if (part is not <symbol> && !list) return 2;
  Var literal = part;
  Symbol tested = <list>;
  _match_and(b, testing);
  if (list) b.printf("Var_is(%s, %lu)", cell, (unsigned long) tested);
  else b.printf("%s.u64 == %lluULL", cell, (unsigned long long) literal.u64);
  return !!list;
}

/* Writes the static `pattern`, whose value is `value`, as nested tests on
   cursors over the subject, each binder a local read from its cell, and
   returns the braces that close them, raising `depths` to the deepest
   cursor they read; or returns -1 and writes nothing for a pattern outside
   that form, including a `*` before the end. A nested List waits in
   `rests` while its cursor walks it, and `path` reaches the List the
   cursor walks within the cached pattern, whose cells literals compare. */
meta static int _match_nested(
  Buffer b, Array out, List pattern, Var value, int &depths) {
  if (!pattern.match(%(expr ? (!or (cache ?) (expr ? (cache ?))))) ||
      value is not <list>)
    return -1;
  _match_flush(b, out);
  Array rests = [], paths = [], seen = [];
  int mark = out.len(), testing = 0, braces = 0, step = 0, deepest = 0;
  List rest = value;
  String path = "";
  b.write(" _x2c_match_cursor = _x2c_match_expr;");
  for (;;) {
    int levels = rests.len();
    String cursor = _match_cursor(levels);
    Var part = rest ? rest.car() : NULL;
    if (rest && !part.is_list_binder()) {
      String cell = %"$cursor->car";
      _match_and(b, testing);
      b.write(cursor);
      step = _match_element(b, part, cell, seen, testing, braces);
      if (step == 1) {
        _match_and(b, testing);
        b.printf("(%s = Var_list(%s), 1)", _match_cursor(levels + 1), cell);
        rests.push(rest);
        paths.push(path);
        if (levels >= deepest) deepest = levels + 1;
        rest = part;
        path = path + "->car)";
        continue;
      }
      if (step == 2) {
        _match_and(b, testing);
        b.printf("Var_equal(%s, ", cell);
        for (int level = levels; level; level--) b.write("Var_list(");
        _match_place(b, out, pattern);
        if (path) b.write(path);
        b.write("->car)");
      }
    }
    else {
      if (!rest) {
        _match_and(b, testing);
        b.printf("!%s", cursor);
      }
      else if (rest.cdr() || part in seen) step = -1;
      else if (part != <*>) {
        seen.push(part);
        _match_bind(b, part, cursor, testing, braces);
      }
      if (step < 0 || !levels) break;
      rest = rests.take_last();
      path = paths.take_last();
      cursor = _match_cursor(levels - 1);
    }
    if (step < 0) break;
    _match_and(b, testing);
    b.printf("(%s = %s->cdr, 1)", cursor, cursor);
    rest = rest.cdr();
    path = path + "->cdr";
  }
  if (step < 0) {
    while (out.len() > mark) out.take_last();
    b.clear();
    return -1;
  }
  if (testing) {
    b.write(") {");
    braces++;
  }
  if (deepest > depths) depths = deepest;
  return braces;
}

// arms

/* Writes the test of `pattern` that captures into the buffer and returns
   the brace that closes it. `sites` numbers the static sites within the
   match. */
meta static int _match_test(Buffer b, Array out, List pattern, int &sites) {
  match (pattern)
    case %(expr ? (call (expr ? (ident (binding ? "Macro_case_pattern")))
                        (args ?template ?labels))): {
      int site = sites++;
      b.printf(
        " static MacroCaseSite _x2c_macro_site_%d; "
        "if (Macro_case_capture_at(&_x2c_macro_site_%d, _x2c_match_expr, ",
        site, site);
      _match_place(b, out, template);
      b.write(", ");
      _match_place(b, out, labels);
      b.write(", &_x2c_match_capture)) {");
      return 1;
    }
  if (((Code) pattern).is_static_pattern()) {
    int site = sites++;
    b.printf(
      " static MatchCaptureSite _x2c_match_site_%d; "
      "if (x2c_match_site_try_capture(&_x2c_match_site_%d, ", site, site);
  }
  else b.write(" if (x2c_match_try_capture(");
  b.write("_x2c_match_expr, List_var(");
  _match_place(b, out, pattern);
  b.write("), &_x2c_match_capture)) {");
  return 1;
}

/* Declares each named binder from its slot of the capture buffer; `?` and
   `*` declare nothing. */
meta static void _match_declare(Buffer b, List binders) {
  int index = -1;
  foreach (Var binder, binders) {
    index++;
    if (binder == <?> || binder == <*>) continue;
    String name = binder.str()[1:];
    if (binder.is_list_binder())
      b.printf(" List %s = Var_list(_x2c_match_values[%d]);", name, index);
    else b.printf(" Var %s = _x2c_match_values[%d];", name, index);
  }
}

/* Writes the arm's body, which then breaks unless a guard decides that
   itself, and the `braces` that close the arm's tests. */
meta static void _match_body(Buffer b, Array out, List body, int braces) {
  int finish = 1;
  match (body) case %(guarded ?inner): {
    body = inner;
    finish = 0;
  }
  _match_place(b, out, body);
  if (finish) b.write(" break;");
  while (braces--) b.write(" }");
}

/* The label that lets the switch reach an arm whose pattern value has the
   head `head` directly, or NULL. The first arm with a head takes its
   `case`, and later arms with that head are reached by falling through.
   The first arm without a head can match anything, so it takes `default`
   and ends the labels. */
meta static String _match_label(Symbol head, Array heads, int &labelling) {
  if (!labelling) return NULL;
  if (!head) {
    labelling = 0;
    return " default: ;";
  }
  if (head in heads) return NULL;
  heads.push(head);
  Var literal = head;
  return %" case ${(unsigned long long) literal.u64}ULL: ;";
}

// the lowering

/* The declarations after the subject: the cursors when an arm reads
   `depths` levels, the deepest any arm reads or -1 when none tests in
   place, and the capture buffer when an arm captures `values`, the most
   any such arm captures or -1 when none does. */
meta static String _match_locals(int depths, int values) {
  Buffer b = Buffer.new(0);
  b.write(";");
  for (int depth = 0; depth <= depths; depth++) {
    b.write(depth ? ", " : " List ");
    b.write(_match_cursor(depth));
  }
  if (depths >= 0) b.write(";");
  if (values > 0)
    b.printf(
      " Var _x2c_match_values[%d]; MatchCaptureBuffer _x2c_match_capture = "
      "{ .values = _x2c_match_values, .capacity = %d };", values, values);
  else if (!values)
    b.write(" MatchCaptureBuffer _x2c_match_capture = { 0 };");
  return b.str_free();
}

/* The match of `subject` over `rows`: a block that reads the subject once
   as a List and declares the arms' cursors and capture buffer, then
   switches on the bits of the subject's head. A label sits before the
   conditional groups around its arm, so the switch still reaches later
   arms when the preprocessor removes that one. */
meta static Code _match_lowered(Code subject, List rows) {
  Buffer b = Buffer.new(0);
  Array out = [], heads = [];
  int labelling = 1, opening = 0, depth = 0, sites = 0;
  int depths = -1, values = -1;
  foreach (List row, rows) {
    match (row) case %(preproc ?(String text)): {
      int nesting = _match_nesting(text);
      _match_place(b, out, row);
      if (nesting > 0 && !depth) opening = out.len() - 1;
      depth += nesting;
      continue;
    }
    List (pattern, body) = row;
    int otherwise = pattern.car() == <*>;
    Var value = otherwise ? %() : ((Code) pattern).pattern_value();
    String label = _match_label(_match_head(value), heads, labelling);
    if (label && depth) out.insert(opening++, label);
    else if (label) b.write(label);
    int braces =
      otherwise ? 0 : _match_nested(b, out, pattern, value, depths);
    if (braces < 0) {
      List binders = _match_binders(value);
      if (binders.len() > values) values = binders.len();
      braces = _match_test(b, out, pattern, sites);
      _match_declare(b, binders);
    }
    _match_body(b, out, body, braces);
  }
  if (labelling) b.write(" default: break;");
  _match_flush(b, out);
  String selector = heads.len()
    ? "_x2c_match_expr ? _x2c_match_expr->car.u64 : 0" : "0";
  List read = subject.convert(%("List")), items = _match_items(out);
  String locals = _match_locals(depths, values);
  return Code.lowered(
    %(block ("List _x2c_match_expr =" $read $locals)
            (switch (expr ("uint64_t") ($selector)) (block @items))));
}

$rewrite($matched)
/** Lowers the bound match `node` to C text around its subject, patterns,
    and bodies. */
meta Code match_lowering(Code node) {
  match (node) case $matched(?subject, *rows):
    return _match_lowered(subject, rows);
  return node;
}
