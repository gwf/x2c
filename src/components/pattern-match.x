/*  pattern-match.x -- match statements

    C text surrounds the subject, patterns, and bodies. A block reads the
    subject once as a List and switches on its head's bits. Lowering steps
    into the embedded nodes. The generated `switch` makes `break` leave
    the match and `continue` reach the enclosing loop. A failed arm
    continues to the next arm.

    Static patterns of literals, unique binders, typed captures, nested
    Lists, and a final `*` use direct cursor tests. Other patterns capture
    through macros or Match, with static sites for fixed pattern values.

    Definitions that reach compile-time operations precede their callers:
    the compiler settles a linked copy's reachability when the copy binds.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"

// C text

meta static void _match_flush(Buffer b, Array out) {
  if (b.len()) {
    out.push(b.str());
    b.clear();
  }
}

meta static void _match_place(Buffer b, Array out, Var node) {
  _match_flush(b, out);
  out.push(node);
}

/* The switch body's block items from `out`: each directive alone, and the
   text and nodes between directives as one item. */
meta static List _match_items(Array out) {
  Array items = [], run = [];
  foreach (Var piece in out) {
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

meta static String _match_cursor(int depth) =>
  depth ? %"_x2c_gensym_match_cursor$depth" : "_x2c_gensym_match_cursor";

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

/* Saves a binder's capture from its cell after the open condition, or,
   for a viewed pattern whose case publishes `binders`, which a case that
   captures nothing leaves empty, in the binder's slot of the capture
   buffer within the condition. Returns 0 for a binder the case does not
   publish. */
meta static int _match_bind(
  Buffer b, Var binder, String cell, Array seen, Array binders, int &testing,
  int &braces) {
  int list = binder.is_list_binder();
  if (binders != NULL) {
    int slot = binders.find(binder);
    if (slot < 0) return 0;
    _match_and(b, testing);
    b.printf(
      "(_x2c_gensym_match_values[%d] = %s%s%s, 1)",
      slot, list ? "List_var(" : "", cell, list ? ")" : "");
    return 1;
  }
  if (testing) {
    b.write(") {");
    braces++;
    testing = 0;
  }
  b.printf(
    " %s _x2c_gensym_match_%s_%d = %s;",
    list ? "List" : "Var", list ? "list" : "value", seen.len() - 1, cell);
  return 1;
}

/* Writes the tests of the element `part` of a static pattern, read from
   `cell`, and returns 0 when they are complete, 1 for a nested List the
   caller walks next, 2 for a literal the caller compares with the
   pattern's own cell, or -1 outside the form the arm can test in place:
   an operator other than a quoted Symbol, a computed part, a repeated
   binder, or a binder the case does not publish. The caller of a viewed
   pattern tests that a cell's view is a List as it enters it, so an empty
   List is walked like any other. */
meta static int _match_element(
  Buffer b, Var part, String cell, Array seen, Array binders, int &testing,
  int &braces) {
  Var binder = part;
  Symbol tag = part is <list> ? _match_capture_tag(part, binder) : 0;
  if (tag) {
    _match_and(b, testing);
    b.printf("Var_is(%s, %lu)", cell, (unsigned long) tag);
    part = binder;
  }
  Var literal = part;
  match (part) case %((!quote !quote) ?(Symbol quoted)): {
    literal = quoted;
    _match_and(b, testing);
    b.printf("%s.u64 == %lluULL", cell, (unsigned long long) literal.u64);
    return 0;
  }
  if (part == <?>) return 0;
  if (part.is_atom_binder() && !(part in seen)) {
    seen.push(part);
    return _match_bind(b, part, cell, seen, binders, testing, braces) ? 0 : -1;
  }
  List list = part is <list> ? part.list() : NULL;
  if (part.is_binder() || part.is_match_op() || part == <x2c-dyn> ||
      (list && list.car().is_match_op()))
    return -1;
  if (part is <list> && binders != NULL) return 1;
  if (part is not <symbol> && !list) return binders != NULL ? -1 : 2;
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
   cursor walks within the cached pattern, whose cells literals compare.

   A viewed pattern, whose case publishes `binders`, empty when it
   captures nothing, continues the open condition of a macro-valued case,
   whose cursor starts on the subject's view. It enters each List through
   its view, captures each of `binders` once into the capture buffer, and
   closes no braces. */
meta static int _match_nested(
  Buffer b, Array out, List pattern, Var value, Array binders, int &depths) {
  int viewed = binders != NULL;
  if ((!viewed &&
       !pattern.match(%(expr ? (!or (cache ?) (expr ? (cache ?)))))) ||
      value is not <list>)
    return -1;
  _match_flush(b, out);
  Array rests = [], paths = [], seen = [];
  int mark = out.len(), testing = viewed, braces = 0, step = 0;
  int deepest = 0;
  List rest = value;
  String path = "";
  if (!viewed)
    b.write(" _x2c_gensym_match_cursor = _x2c_gensym_match_expr;");
  for (;;) {
    int levels = rests.len();
    String cursor = _match_cursor(levels);
    Var part = rest ? rest.car() : NULL;
    if (rest && !part.is_list_binder()) {
      String cell = %"$cursor->car";
      _match_and(b, testing);
      b.write(cursor);
      step = _match_element(b, part, cell, seen, binders, testing, braces);
      if (step == 1) {
        _match_and(b, testing);
        String next = _match_cursor(levels + 1);
        if (viewed) b.printf("Macro_case_enter(%s, &%s)", cell, next);
        else b.printf("(%s = Var_list_payload(%s), 1)", next, cell);
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
        for (int level = levels; level; level--) b.write("Var_list_payload(");
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
        if (!_match_bind(b, part, cursor, seen, binders, testing, braces))
          step = -1;
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
  if (viewed && seen.len() < binders.len()) step = -1;
  if (step < 0) {
    while (out.len() > mark) out.take_last();
    b.clear();
    return -1;
  }
  if (testing && !viewed) {
    b.write(") {");
    braces++;
  }
  if (deepest > depths) depths = deepest;
  return braces;
}

// arms

/* Copies runtime capture slots to the values the ordinary arm reads. */
meta static void _match_captures(Buffer b, List binders) {
  int index = 0;
  foreach (Atom binder in binders) {
    int list = binder.is_list_binder();
    b.printf(
      " %s _x2c_gensym_match_%s_%d = %s_x2c_gensym_match_values[%d]%s;",
      list ? "List" : "Var", list ? "list" : "value", index,
      list ? "Var_list_payload(" : "", index, list ? ")" : "");
    index++;
  }
}

/* Writes the case of the macro value `template` with the `labels` the arm
   publishes as `binders` as nested tests of `shape`, the pattern the case
   derived, and returns the braces that close them; or returns -1 and
   writes nothing when `_match_nested` cannot test it in place. The case's
   rules hold: `Macro_case_root` captures a retained invocation of the
   macro, or starts the tests on the subject's view, or on the one
   statement a `seq` holds when the body is a statement, and each List the
   tests enter is viewed the same way. `Macro_case_start` first decides a
   subject that is its own view without that call. */
meta static int _match_viewed(
  Buffer b, Array out, List template, List labels, Code shape, List binders,
  int &depths) {
  Var derived = shape.pattern_value();
  int statement = 0;
  match (derived) case %((!quote !or) ?single (seq ?again)): {
    Symbol head = _match_head(single);
    if (head && head != <seq> && single.equal(again)) {
      derived = single;
      statement = 1;
    }
  }
  Buffer tests = Buffer.new(0);
  if (_match_nested(tests, [], NULL, derived, binders, depths) < 0)
    return -1;
  b.write(" { int _x2c_gensym_match_root = ");
  Symbol head = _match_head(derived);
  if (head && !(head in %(at src seq)))
    b.printf(
      "Macro_case_start(_x2c_gensym_match_expr, %lluULL, "
      "&_x2c_gensym_match_cursor); if (_x2c_gensym_match_root < 0) "
      "_x2c_gensym_match_root = ",
      (unsigned long long) head);
  b.write("Macro_case_root(_x2c_gensym_match_expr, ");
  _match_place(b, out, template);
  b.write(", ");
  _match_place(b, out, labels);
  b.printf(
    ", %d, &_x2c_gensym_match_cursor, &_x2c_gensym_match_capture); "
    "if (_x2c_gensym_match_root == 1 || (_x2c_gensym_match_root == 2%s)) {",
    statement, tests.str_free());
  return 2;
}

/* Writes the test of `pattern` that captures its `binders` into the
   buffer and returns the braces that close it. A macro-valued case whose
   derived pattern the compiler kept is tested in place when it can be.
   `sites` numbers the static sites within the match. */
meta static int _match_test(
  Buffer b, Array out, List pattern, List binders, int &sites, int &depths) {
  match (pattern)
    case %(expr ? (call (expr ? (ident (binding ? (!or "Macro_case_pattern"
                                                     "Macro_case_shape"))))
                        (args ?template ?labels *shape))): {
      int braces = shape
        ? _match_viewed(b, out, template, labels, shape.car(), binders, depths)
        : -1;
      if (braces >= 0) return braces;
      int site = sites++;
      b.printf(
        " static MacroCaseSite _x2c_gensym_macro_site_%d; "
        "if (Macro_case_capture_at(&_x2c_gensym_macro_site_%d, "
        "_x2c_gensym_match_expr, ",
        site, site);
      _match_place(b, out, template);
      b.write(", ");
      _match_place(b, out, labels);
      b.write(", &_x2c_gensym_match_capture)) {");
      return 1;
    }
  if (((Code) pattern).is_static_pattern()) {
    int site = sites++;
    b.printf(
      " static MatchCaptureSite _x2c_gensym_match_site_%d; "
      "if (x2c_match_site_try_capture(&_x2c_gensym_match_site_%d, ",
      site, site);
  }
  else b.write(" if (x2c_match_try_capture(");
  b.write("_x2c_gensym_match_expr, List_var(");
  _match_place(b, out, pattern);
  b.write("), &_x2c_gensym_match_capture)) {");
  return 1;
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
  return %" case $((unsigned long long) literal.u64)ULL: ;";
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
      " Var _x2c_gensym_match_values[%d]; "
      "MatchCaptureBuffer _x2c_gensym_match_capture = "
      "{ .values = _x2c_gensym_match_values, .capacity = %d };",
      values, values);
  else if (!values)
    b.write(" MatchCaptureBuffer _x2c_gensym_match_capture = { 0 };");
  return b.str_free();
}

/* The match of `subject` over `rows`: a block that reads the subject once
   as a List and declares the arms' cursors and capture buffer, then
   switches on the bits of the subject's head. A label sits before the
   conditional groups around its arm, so the switch still reaches later
   arms when the preprocessor removes that one. A `Var` subject whose tag
   is not `<list>` is no List: every List arm is skipped, and only a `*`
   arm runs. */
meta static Code _match_lowered(Code subject, List rows) {
  Buffer b = Buffer.new(0);
  Array out = [], heads = [];
  int labelling = 1, opening = 0, depth = 0, sites = 0;
  int depths = -1, values = -1;
  int dynamic = subject.type().is_named("Var");
  foreach (List row in rows) {
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
    int guarded = dynamic && !otherwise;
    if (guarded) b.write(" if (!_x2c_gensym_match_none) {");
    int braces =
      otherwise ? 0 : _match_nested(b, out, pattern, value, NULL, depths);
    if (braces < 0) {
      List binders = _match_binders(value);
      if (binders.len() > values) values = binders.len();
      braces = _match_test(b, out, pattern, binders, sites, depths);
      _match_captures(b, binders);
    }
    _match_body(b, out, body, braces + guarded);
  }
  if (labelling) b.write(" default: break;");
  _match_flush(b, out);
  String selector = heads.len()
    ? "_x2c_gensym_match_expr ? _x2c_gensym_match_expr->car.u64 : 0" : "0";
  List items = _match_items(out);
  String locals = _match_locals(depths, values);
  List prologue = dynamic
    ? _match_dynamic_read(subject, locals)
    : $("List _x2c_gensym_match_expr =", subject.convert(%("List")), locals);
  return Code.lowered(
    %(block $prologue
            (switch (expr ("uint64_t") ($selector)) (block @items))), NULL);
}

/* The reads of a `Var` subject: once into a local, then as a List, with
   `_x2c_gensym_match_none` set when its tag is not `<list>`. */
meta static List _match_dynamic_read(Code subject, String locals) {
  Symbol list = <list>;
  String tested = "; int _x2c_gensym_match_none = "
    "!Var_is(_x2c_gensym_match_var, %lu);"
    .printf((unsigned long) list);
  return $(
    "Var _x2c_gensym_match_var =", subject, tested,
    "List _x2c_gensym_match_expr = Var_list_payload(_x2c_gensym_match_var)",
    locals);
}

$rewrite($matched)
/** Lowers the bound match `node` to C text around its subject, patterns,
    and bodies. */
meta Code match_lowering(Code node) {
  match (node) case $matched(?subject, *rows):
    return _match_lowered(subject, rows);
  return node;
}
