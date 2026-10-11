/*  component-match.x -- match statements

    A match lowers to C text around its subject, patterns, and bodies: a
    block that reads the subject once as a List, declares the buffer the
    arms capture into, and switches on the subject's head Symbol. Lowering
    steps into the nodes the text holds, and the `switch` is the barrier
    the cleanup walk knows, so an arm's `break` leaves the match and
    `continue` reaches the enclosing loop. Each arm tests its pattern,
    declares its binders, runs its body, and breaks; an arm that fails
    falls into the next. A flat pattern, a head Symbol and a capture of
    each binder, is tested in place; a macro-valued case recognizes through
    its macro; any other pattern calls the Match runtime, through a static
    site when the pattern's value is the same each time it runs.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"

// C text

/* Ends the C text written to `b` and places `node` after it in `out`. */
meta static void _match_place(Buffer b, Array out, Var node) {
  if (b.len()) {
    out.push(b.str());
    b.clear();
  }
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

/* The tag a typed capture `(!is ?name type <tag>)` of `binder` tests, or
   0. The runtime canonicalizes `varray` and `vmap`, so those keep the
   Match call. */
meta static Symbol _match_capture_tag(Var element, Var binder) {
  match (element)
    case %((!quote !is) ?name type ?(Symbol tag)):
      if (name == binder && tag != <x2c-dyn> && tag != <varray> &&
          tag != <vmap>)
        return tag;
  return 0;
}

// arms

/* Writes the test of a flat pattern, a head Symbol and a capture of each
   binder in order, typed or not, and returns 1; or returns 0 and writes
   nothing. The head is tested even under head dispatch, because a failed
   arm falls into the next. */
meta static int _match_flat_test(Buffer b, Var value, List binders) {
  Symbol head = _match_head(value);
  if (!head) return 0;
  Var literal = head;
  size_t start = b.len();
  b.printf(
    " { List _x2c_match_cursor; if (_x2c_match_expr && "
    "_x2c_match_expr->car.u64 == %lluULL && "
    "(_x2c_match_cursor = _x2c_match_expr->cdr, 1)",
    (unsigned long long) literal.u64);
  List elements = value.list().cdr();
  int index = 0;
  foreach (Var binder, binders) {
    Var element = elements ? elements.car() : NULL;
    Symbol tag = element == binder ? 0 : _match_capture_tag(element, binder);
    if (!elements || !binder.is_atom_binder() || binder == <?> ||
        (element != binder && !tag)) {
      b.unwrite(b.len() - start);
      return 0;
    }
    b.write(" && _x2c_match_cursor");
    if (tag)
      b.printf(" && Var_is(_x2c_match_cursor->car, %lu)", (unsigned long) tag);
    b.printf(
      " && (_x2c_match_values[%d] = _x2c_match_cursor->car, "
      "_x2c_match_cursor = _x2c_match_cursor->cdr, 1)", index++);
    elements = elements.cdr();
  }
  if (elements) {
    b.unwrite(b.len() - start);
    return 0;
  }
  b.write(" && !_x2c_match_cursor) {");
  return 1;
}

/* Writes the test that opens the arm of `pattern`, whose value is
   `value`, and returns the number of braces that close the arm. `sites`
   numbers the static sites within the match. */
meta static int _match_test(
  Buffer b, Array out, List pattern, Var value, List binders, int &sites) {
  if (pattern.car() == <*>) return 0;
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
  if (_match_flat_test(b, value, binders)) return 2;
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

/* Writes the arm that runs `body` when `pattern` matches: its test, its
   binders, and the body, which then breaks unless a guard decides that
   itself. */
meta static void _match_arm(
  Buffer b, Array out, List pattern, Var value, List binders, List body,
  int &sites) {
  int finish = 1;
  match (body) case %(guarded ?inner): {
    body = inner;
    finish = 0;
  }
  int braces = _match_test(b, out, pattern, value, binders, sites);
  _match_declare(b, binders);
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
  return %" case ${(long) head}: ;";
}

// the lowering

/* The match of `subject` over `rows`: a block that reads the subject once
   as a List and declares the capture buffer, then switches on the
   subject's head Symbol. A label sits before the conditional groups
   around its arm, so the switch still reaches later arms when the
   preprocessor removes that one. */
meta static Code _match_lowered(Code subject, List rows) {
  Buffer b = Buffer.new(0);
  Array out = [], heads = [];
  int labelling = 1, opening = 0, depth = 0, values = 0, sites = 0;
  foreach (List row, rows) {
    match (row) case %(preproc ?(String text)): {
      int nesting = _match_nesting(text);
      _match_place(b, out, row);
      if (nesting > 0 && !depth) opening = out.len() - 1;
      depth += nesting;
      continue;
    }
    List (pattern, body) = row;
    Var value = pattern.car() == <*> ? %() : ((Code) pattern).pattern_value();
    List binders = _match_binders(value);
    if (binders.len() > values) values = binders.len();
    String label = _match_label(_match_head(value), heads, labelling);
    if (label && depth) out.insert(opening++, label);
    else if (label) b.write(label);
    _match_arm(b, out, pattern, value, binders, body, sites);
  }
  if (labelling) b.write(" default: break;");
  if (b.len()) out.push(b.str());
  String buffer = values
    ? %"Var _x2c_match_values[$values]; MatchCaptureBuffer "
      + "_x2c_match_capture = { .values = _x2c_match_values, "
      + %".capacity = $values };"
    : "MatchCaptureBuffer _x2c_match_capture = { 0 };";
  String selector = heads.len() ? "Var_symbol(car(_x2c_match_expr))" : "0";
  List read = subject.convert(%("List")), items = _match_items(out);
  return Code.lowered(
    %(block ("List _x2c_match_expr =" $read ";" $buffer)
            (switch (expr (int) ($selector)) (block @items))));
}

$rewrite($matched)
/** Lowers the bound match `node` to C text around its subject, patterns,
    and bodies. */
meta Code match_lowering(Code node) {
  match (node) case $matched(?subject, *rows):
    return _match_lowered(subject, rows);
  return node;
}
