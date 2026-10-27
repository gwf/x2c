/*  pattern-match.x -- match statements

    A match lowers to a block that reads the subject once as a List and
    switches on its head's bits. The generated `switch` makes `break` leave
    the match and `continue` reach the enclosing loop. A failed arm
    continues to the next arm.

    A static pattern first becomes a tree of tests on single values joined
    by and, or, and not, so every Match operator is tested in place; only a
    `*` segment before the end of a List needs Match's search. Other
    patterns capture through macros or Match, with static sites for fixed
    pattern values. The block that reads the subject is a quotation, which
    the rule's caller binds. The switch inside it is placed: the transform
    lowers only the arm bodies it holds, and the emit module renders the
    rest as C text.

    Definitions that reach compile-time operations precede their callers:
    the compiler settles a linked copy's reachability when the copy binds.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"

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

/* The position of `binder` in `binders`, or -1. */
meta static int _match_slot(List binders, Var binder) {
  int slot = 0;
  foreach (Var name in binders) {
    if (name == binder) return slot;
    slot++;
  }
  return -1;
}

/* Collects each distinct binder outside `!quote` in first-appearance
   order, and returns 0 when a `*name` repeats, which no test compares. */
meta static int _match_names(Var part, Array names) {
  if (part is <list> && !part.is_nil()) {
    List list = part;
    if (list.car() == <!quote>) return 1;
    foreach (Var element in list)
      if (!_match_names(element, names)) return 0;
    return 1;
  }
  if (!part.is_binder() || part == <?> || part == <*>) return 1;
  if (part in names) return !part.is_list_binder();
  names.push(part);
  return 1;
}

/* The local that carries the arm's `index`th capture into its body, by
   the name `Compiler.match_capture_value` reads. */
meta static List _match_capture(Var binder, int index) {
  String kind = binder.is_list_binder() ? "list" : "value";
  return %(ident (binding-name $(%"x2c_match_$(kind)_$index")));
}

// pattern tests

/* A static pattern first becomes a tree of tests: (and T ...),
   (or T ...), (not T), (true), and leaves that test one cell. A cell is a
   cursor whose head holds a value; `<subject>` is the subject itself,
   `<root>` its first cell, and any other cell numbers the new cursor whose
   entry in `cursors` is `(first)` when it starts a List or `(cdr PRIOR)`.
   Building the tree reaches no compile-time operation, so these functions
   may call each other in any order. A literal that compares by value
   records the `steps`,
   `<cdr>` or `<in>`, that reach its cell in the cached pattern, latest
   first. NULL marks a pattern these tests do not cover; Match tests it
   instead. */

meta static int _match_fresh(Array cursors, List how) {
  cursors.push(how);
  return cursors.len() - 1;
}

/* The tests of the pattern `value` on the subject. */
meta static List _match_tests(List value, Array cursors) =>
  value && value.car().is_match_op()
    ? _match_guard(value.car(), value.cdr(), <subject>, NULL, cursors)
    : _match_list(value, <root>, NULL, cursors);

/* The tests of `part` on the value in `cell`, whose pattern cell `steps`
   reach. */
meta static List _match_value(
  Var part, Var cell, List steps, Array cursors) {
  if (part == <?>) return %(true);
  if (part.is_atom_binder()) return %(bind $cell $part);
  if (part.is_list_binder() || part == <x2c-dyn>) return NULL;
  if (part is <symbol>) return %(bits $cell $part);
  if (part is not <list> || part.is_nil()) return %(equal $cell $steps);
  List list = part;
  steps = cons(<in>, steps);
  if (list.car() == <x2c-dyn>) return NULL;
  if (list.car().is_match_op())
    return _match_guard(list.car(), list.cdr(), cell, steps, cursors);
  if (cell == <subject>) return _match_list(list, <root>, steps, cursors);
  Var first = <none>;
  if (list.car() != <*> || list.cdr()) first = _match_fresh(cursors, %(first));
  List tests = _match_list(list, first, steps, cursors);
  return tests ? %(and (listp $cell $first) $tests) : NULL;
}

/* The tests of a List whose first cell is `at` and whose first element
   `steps` reach. Only a final `*` or `*name` spans elements. */
meta static List _match_list(
  List list, Var at, List steps, Array cursors) {
  Array tests = [];
  for (;; list = list.cdr()) {
    if (!list) {
      tests.push(%(end $at));
      break;
    }
    Var part = list.car();
    if (part.is_list_binder()) {
      if (list.cdr()) return NULL;
      if (part != <*>) tests.push(%(rest $at $part));
      break;
    }
    List test = _match_value(part, at, steps, cursors);
    if (!test) return NULL;
    tests.push(%(some $at));
    if (test.car() != <true>) tests.push(test);
    List next = list.cdr();
    if (!next || next.car() != <*> || next.cdr())
      at = _match_fresh(cursors, %(cdr $at));
    steps = cons(<cdr>, steps);
  }
  return %(and @(tests.list_free()));
}

/* The tests of a guard on the value in `cell` itself, whose operands
   follow `steps`. Each leading binder followed by an operand captures that
   value, as Match normalizes `(OP ?b PAT ...)` to
   `(!set ?b (OP PAT ...))` again until no binder leads. */
meta static List _match_guard(
  Var op, List args, Var cell, List steps, Array cursors) {
  steps = cons(<cdr>, steps);
  if (op == <!quote>) {
    if (!args || args.cdr()) return NULL;
    return args.car() is <symbol> ? %(bits $cell $(args.car()))
                                  : %(equal $cell $steps);
  }
  Array tests = [];
  while (args && args.car().is_binder() && args.cdr()) {
    if (args.car().is_list_binder()) return NULL;
    if (args.car() != <?>) tests.push(%(bind $cell $(args.car())));
    args = args.cdr();
    steps = cons(<cdr>, steps);
  }
  if (op == <!is>) {
    List test = _match_is(args, cell);
    if (!test) return NULL;
    tests.push(test);
    return %(and @(tests.list_free()));
  }
  Array operands = [];
  foreach (Var operand in args) {
    List test = _match_value(operand, cell, steps, cursors);
    if (!test) return NULL;
    operands.push(test);
    steps = cons(<cdr>, steps);
  }
  List choice = %(or @(operands.list_free()));
  if (op == <!and>) choice = %(and @(choice.cdr()));
  else if (op == <!not>) choice = %(not $choice);
  else if (op != <!or> && op != <!set>) return NULL;
  tests.push(choice);
  return %(and @(tests.list_free()));
}

/* The test of `(!is ...)` operands on the value in `cell`. */
meta static List _match_is(List args, Var cell) {
  match (args) {
    case %(var binder): return %(kind $cell "is_atom_binder");
    case %(list binder): return %(kind $cell "is_list_binder");
    case %(binder): return %(kind $cell "is_binder");
    case %(op): return %(kind $cell "is_match_op");
    case %(atom): return %(atom $cell);
    case %(type ?(Symbol tag)): {
      if (tag == <x2c-dyn>) return NULL;
      if (tag == <varray>) tag = <array>;
      if (tag == <vmap>) tag = <map>;
      return %(tag $cell $tag);
    }
  }
  return NULL;
}

/* Whether a macro-valued case can run `test` in place: its view rules
   cover entering Lists, literal Symbols, and tags, and its relation
   compares repeated binders, so a choice, negation, category, value
   comparison, or repeated binder keeps the case's Match call. */
meta static int _match_viewable(List test, Array seen) {
  Var op = test.car();
  if (op == <or> || op == <not> || op == <kind> || op == <atom> ||
      op == <equal>)
    return 0;
  match (test) case %((!or bind rest) ? ?binder): {
    if (binder in seen) return 0;
    seen.push(binder);
  }
  foreach (Var part in test.cdr())
    if (part is <list> && !_match_viewable(part, seen)) return 0;
  return 1;
}

/* Whether every binder that `test` sets again meets one state on every
   path: set by every earlier alternative, or by none. Match decides the
   others while it runs, so those arms keep its call. `bound` holds the
   binders this path has set and `unsure` those only some paths set. */
meta static int _match_settled(List test, Array bound, Array unsure) {
  match (test) {
    case %(and *parts): {
      foreach (List part in parts)
        if (!_match_settled(part, bound, unsure)) return 0;
    }
    case %(or *parts): {
      Array every = NULL, some = [];
      foreach (List part in parts) {
        Array mine = bound.copy();
        if (!_match_settled(part, mine, unsure)) return 0;
        Array both = [];
        foreach (Var name in mine) {
          if (every == NULL || name in every) both.push(name);
          if (!(name in some)) some.push(name);
        }
        every = both;
      }
      foreach (Var name in some)
        if (every == NULL || !(name in every)) unsure.push(name);
        else if (!(name in bound)) bound.push(name);
    }
    case %(not ?inner): return _match_settled(inner, bound.copy(), unsure);
    case %((!or bind rest) ? ?binder): {
      if (binder in unsure) return 0;
      if (!(binder in bound)) bound.push(binder);
    }
  }
  return 1;
}

// writing tests

/* The tests are finished expressions: each operator is the node the
   emitter prints, over raw bindings, names, and literals, so nothing in
   them is typed, bound, or lowered again. */

/* The runtime method `name` of the type named `owner`, as the typed
   function its binding names, so a call needs no lookup. */
meta static List _match_method(String owner, String name) {
  Type type = $(owner);
  match (type.resolve_member(name, 1))
    case %(method ?binding ?(List signature)): {
      Type callable = signature;
      return $!($callable){ $binding };
    }
  return NULL;
}

/* The `int` literal `value`. */
meta static List _match_int(int value) {
  switch (value) {
    case 0: return %(literal (int) "0");
    case 1: return %(literal (int) "1");
    case 2: return %(literal (int) "2");
  }
  return %(literal (int) $(%"$value"));
}

/* The conditions `parts` as one `m-all` or `m-any` node, as `kind`
   names, or the one condition or constant that holds the same. */
meta static List _match_joined(Symbol kind, Array parts) {
  if (parts.len() == 1) return parts[0];
  if (!parts.len()) return _match_int(kind == <m-all>);
  return $(kind, @(parts.list_free()));
}

/* The `uint64_t` literal of the bits of `value`. */
meta static List _match_bits(Var value) {
  unsigned long long bits = value.u64;
  return %(literal (uint64_t) $(%"$(bits)ULL"));
}

/* The cursor `cell` names: the subject's first cell is `root`, and a
   numbered cell is the binding of its row in `cursors`. */
meta static List _match_cursor(Var cell, List root, Array cursors) {
  if (cell == <root>) return root;
  List row = cursors[cell.int()];
  return row.car();
}

/* The value `cell` holds. */
meta static List _match_held(Var cell, List root, Array cursors) {
  if (cell == <subject>) return %(call List_var (args $root));
  return %(op -> $(_match_cursor(cell, root, cursors)) car);
}

/* The cell of the cached `pattern` that `steps`, latest first, reach. */
meta static List _match_literal(Code pattern, List steps) {
  List cell = pattern;
  foreach (Var step in steps.reverse())
    cell = step == <in> ? %(call Var_list_payload (args (op -> $cell car)))
                        : %(op -> $cell cdr);
  return %(op -> $cell car);
}

/* `left` assigned `right` as a test that always holds. */
meta static List _match_assigned(List left, List right) =>
  %(commas (op = $left $right) $(_match_int(1)));

/* Appends to `parts` the steps that bring the cursor `cell` from the one
   before it, unless this path has it. A List's first cursor is assigned as
   the List is tested. */
meta static void _match_need(
  Var cell, Array cursors, Array ready, List root, Array parts) {
  if (cell is <symbol> || cell in ready) return;
  List row = cursors[cell.int()];
  match (row) case %(? (cdr ?prior)): {
    _match_need(prior, cursors, ready, root, parts);
    List source = _match_cursor(prior, root, cursors);
    parts.push(%(m-next $(_match_cursor(cell, root, cursors)) $source));
    ready.push(cell);
  }
}

/* `at`, or the assignment of `at` when the last of `parts` steps to it, so
   the step itself tests the cursor. */
meta static List _match_stepped(Array parts, List at) {
  int last = parts.len() - 1;
  if (last >= 0 && (parts[last] ~= %(m-next ?cursor ?prior)) &&
      cursor === at) {
    parts.take_last();
    return %(m-step $at $prior);
  }
  return at;
}

/* Appends to `parts` the condition of the leaf `test` on the value in
   `cell`, after any steps that reach it. */
meta static void _match_leaf(
  List test, Var cell, Code pattern, List root, Array cursors, Array ready,
  Array bound, Map locals, Array parts) {
  _match_need(cell, cursors, ready, root, parts);
  List held = _match_held(cell, root, cursors);
  List at = cell == <subject> ? NULL : _match_cursor(cell, root, cursors);
  List tested = NULL;
  Symbol tagged = <list>;
  List list = $!Symbol{ $tagged };
  match (test) {
    case %(some ?): tested = _match_stepped(parts, at);
    case %(end ?): tested = %(op ! $(_match_stepped(parts, at)));
    case %(listp ? ?first): {
      List listed = %(call Var_is (args $held $list));
      if (first == <none>)
        tested = pattern ? listed
                         : $!int{ Macro_case_enter($held, &(List){0}) };
      else {
        List cursor = _match_cursor(first, root, cursors);
        List payload = %(call Var_list_payload (args $held));
        ready.push(first);
        tested = pattern
          ? %(op && $listed $(_match_assigned(cursor, payload)))
          : %(call Macro_case_enter (args $held (op & $cursor)));
      }
    }
    case %(atom ?): tested = %(op ! (call Var_is (args $held $list)));
    case %(bits ? ?literal):
      tested = at ? %(m-bits $at $(_match_bits(literal)))
                  : %(op == (op . $held u64) $(_match_bits(literal)));
    case %(tag ? ?(Symbol tag)):
      tested = %(call Var_is (args $held $($!Symbol{ $tag })));
    case %(kind ? ?(String predicate)):
      tested = %(call $(_match_method("Var", predicate)) (args $held));
    case %(equal ? ?steps): {
      List literal = _match_literal(pattern, steps);
      tested = %(call Var_equal (args $held $literal));
    }
    case %(bind ? ?binder): {
      List local = locals[binder];
      if (binder in bound) tested = %(call Var_equal (args $held $local));
      else {
        bound.push(binder);
        tested = at ? %(m-take $local $at) : _match_assigned(local, held);
      }
    }
    case %(rest ? ?binder): {
      List local = locals[binder];
      bound.push(binder);
      tested = _match_assigned(
        local, pattern ? at : %(call List_var (args $at)));
    }
  }
  parts.push(tested);
}

/* Appends the conditions `test` writes to `parts`. `ready` holds the
   cursors this path has assigned and `bound` the binders it has set, so a
   repeated binder compares; an alternative or a negation works on copies,
   and binders that every alternative sets stay set after the choice.
   `locals` holds the lvalue of each binder, and a macro-valued case has no
   `pattern`. */
meta static void _match_conditions(
  List test, Code pattern, List root, Array cursors, Array ready,
  Array bound, Map locals, Array parts) {
  match (test) {
    case %(true): return;
    case %(and *items): {
      foreach (List part in items)
        _match_conditions(
          part, pattern, root, cursors, ready, bound, locals, parts);
    }
    case %(or *items): {
      Array choices = [];
      Array common = NULL;
      foreach (List part in items) {
        Array mine = bound.copy(), choice = [];
        _match_conditions(
          part, pattern, root, cursors, ready.copy(), mine, locals, choice);
        choices.push(_match_joined(<m-all>, choice));
        Array both = [];
        foreach (Var name in mine)
          if (common == NULL || name in common) both.push(name);
        common = both;
      }
      if (common != NULL)
        foreach (Var name in common) if (!(name in bound)) bound.push(name);
      parts.push(_match_joined(<m-any>, choices));
    }
    case %(not ?inner): {
      Array none = [];
      _match_conditions(
        inner, pattern, root, cursors, ready.copy(), bound.copy(), locals,
        none);
      parts.push(%(op ! $(_match_joined(<m-all>, none))));
    }
    case %(? ?cell *):
      _match_leaf(
        test, cell, pattern, root, cursors, ready, bound, locals, parts);
  }
}

/* The condition `test` writes, as one node. */
meta static List _match_condition_of(
  List test, Code pattern, List root, Array cursors, Array ready,
  Array bound, Map locals) {
  Array parts = [];
  _match_conditions(test, pattern, root, cursors, ready, bound, locals, parts);
  return _match_joined(<m-all>, parts);
}

/* The rows `(BINDING HOW)` that name each numbered cursor's `HOW`. */
meta static Array _match_named(Array cursors, Array pool) {
  Array rows = [];
  int index = 0;
  foreach (List how in cursors) {
    if (index == pool.len()) pool.push(x2c_binding_fresh("match_at"));
    rows.push($(pool[index++], how));
  }
  return rows;
}

// arms

/* Everything inside the switch is finished code, placed as the nodes the
   emitter prints, untyped below a declaration: nothing in an arm is bound
   or lowered again. The transform lowers only the source a placed switch
   holds, such as each arm body, so a nested match lowers. */

/* The declaration of `binding` as `type`, initialized to `value` when it
   is given. The initializer carries its type for the passes that read
   declarations. */
meta static List _match_declare(Type type, List binding, List value) =>
  value
    ? %(declare $type (bindings (op = (bind $binding ()) (expr $type $value))))
    : %(declare $type (bindings (bind $binding ())));

/* Adds a declaration of each cursor the tests assign to `declared`. */
meta static void _match_cursors(Array cursors, Array declared) {
  Array names = [];
  foreach (List row in cursors) names.push(%(bind $(row.car()) ()));
  if (names.len())
    declared.push(%(declare ("List") (bindings @(names.list_free()))));
}

/* The names a match shares across its arms: its List subject, the flag
   that a `Var` subject is no List, the cursor a macro-valued case starts,
   and the capture buffer with its values. Only the subject and, for a
   `Var` subject, the flag are named at first; `_match_capturing` names the
   rest when an arm captures through Match. */
meta static List _match_frame(Code subject) => $(
  x2c_binding_fresh("match_expr"),
  subject.type().is_named("Var") ? x2c_binding_fresh("match_none") : NULL,
  NULL, NULL, NULL);

/* `frame` with the names an arm that captures through Match uses. */
meta static List _match_capturing(List frame) {
  List (expr, none, cursor) = frame;
  if (cursor) return frame;
  return $(expr, none, x2c_binding_fresh("match_cursor"),
           x2c_binding_fresh("match_capture"),
           x2c_binding_fresh("match_values"));
}

/* The declarations that copy capture slots to the locals the arm body
   reads. */
meta static List _match_captures(List binders, List values) {
  Array copied = [];
  int index = 0;
  foreach (Atom binder in binders) {
    List local = _match_capture(binder, index);
    List slot = %(index $values $(_match_int(index)));
    if (binder.is_list_binder()) {
      List payload = %(call Var_list_payload (args $slot));
      copied.push(_match_declare(%("List"), local, payload));
    }
    else copied.push(_match_declare(%("Var"), local, slot));
    index++;
  }
  return copied.list_free();
}

/* The arm that tests the cached `pattern`, whose value is `value`, in
   place and then runs `finished`; or NULL when the tests do not cover it.
   The tests set a local for each binder: a definite binder's is the one
   the arm body reads, and its cursors take names from `pool`, which every
   arm of the match shares. */
meta static List _match_arm(
  List pattern, Var value, List expr, List finished, Array pool) {
  if (!pattern.match(%(expr ? (!or (cache ?) (expr ? (cache ?))))) ||
      value is not <list>)
    return NULL;
  Array names = [], cursors = [];
  Map locals = {};
  if (!_match_names(value, names)) return NULL;
  List test = _match_tests(value, cursors);
  if (!test || !_match_settled(test, [], [])) return NULL;
  cursors = _match_named(cursors, pool);
  List definite = _match_binders(value);
  Array declared = [];
  _match_cursors(cursors, declared);
  Array values = [], lists = [];
  foreach (Var name in names) {
    int slot = _match_slot(definite, name);
    List local = slot >= 0 ? _match_capture(name, slot)
                           : x2c_binding_fresh("match_bound");
    locals[name] = local;
    (name.is_list_binder() ? lists : values).push(%(bind $local ()));
  }
  if (values.len())
    declared.push(%(declare ("Var") (bindings @(values.list_free()))));
  if (lists.len())
    declared.push(%(declare ("List") (bindings @(lists.list_free()))));
  List condition = _match_condition_of(
    test, (Code) pattern, expr, cursors, [], [], locals);
  declared.push(%(if $condition $finished));
  return %(block @(declared.list_free()));
}

/* The case of the macro value `template` with the `labels` the arm
   publishes as `binders`, tested in place on `shape`, the pattern the
   case derived, then running `finished`; or NULL when the tests do not
   cover it or a binder is not one the case publishes. The case's rules
   hold: `Macro_case_root` captures a retained invocation of the macro, or
   starts the tests on the subject's view, or on the one statement a `seq`
   holds when the body is a statement, and each List the tests enter is
   viewed the same way. `Macro_case_start` first decides a subject that is
   its own view without that call. Each binder is written to its slot in
   the capture buffer. */
meta static List _match_viewed(
  List template, List labels, Code shape, List binders, List frame,
  List finished, Array pool) {
  List (expr, none, cursor, capture, values) = frame;
  Var derived = shape.pattern_value();
  int statement = 0;
  match (derived) case %((!quote !or) ?single (seq ?again)): {
    Symbol head = _match_head(single);
    if (head && head != <seq> && single.equal(again)) {
      derived = single;
      statement = 1;
    }
  }
  Array names = [], cursors = [];
  Map locals = {};
  if (derived is not <list> || !_match_names(derived, names) ||
      names.len() != binders.len() ||
      _match_binders(derived).len() != binders.len())
    return NULL;
  foreach (Var name in names) {
    int slot = _match_slot(binders, name);
    if (slot < 0) return NULL;
    locals[name] = %(index $values $(_match_int(slot)));
  }
  List test = _match_tests(derived, cursors);
  if (!test || !_match_viewable(test, [])) return NULL;
  cursors = _match_named(cursors, pool);
  List condition =
    _match_condition_of(test, NULL, cursor, cursors, [], [], locals);
  Array declared = [];
  _match_cursors(cursors, declared);
  List state = x2c_binding_fresh("match_root");
  List rooted = %(call Macro_case_root (args $expr $template $labels
    $(_match_int(statement)) (op & $cursor) (op & $capture)));
  Symbol head = _match_head(derived);
  if (head && !(head in %(at src seq))) {
    List started = %(call Macro_case_start
      (args $expr $($!Symbol{ $head }) (op & $cursor)));
    List missed = %(op < $state $(_match_int(0)));
    List again = %(stmnt (op = $state $rooted));
    declared.push(_match_declare(%(int), state, started));
    declared.push(%(if $missed $again));
  }
  else declared.push(_match_declare(%(int), state, rooted));
  List chosen = %(op || (op == $state $(_match_int(1)))
                        (op && (op == $state $(_match_int(2))) $condition));
  List body = _match_captures(binders, values);
  declared.push(%(if $chosen (block @body $finished)));
  return %(block @(declared.list_free()));
}

/* The arm that captures `binders` through Match and then runs `finished`:
   a macro-valued case tested in place when it can be, through its case
   site otherwise, or the pattern at a static site when it is fixed. */
meta static List _match_fallback(
  List pattern, List binders, List frame, List finished, int &viewing,
  Array pool) {
  List (expr, none, cursor, capture, values) = frame;
  List body = _match_captures(binders, values);
  List buffer = %(op & $capture);
  List boxed = %(call List_var (args $pattern));
  match (pattern)
    case %(expr ? (call (expr ? (ident (binding ? (!or "Macro_case_pattern"
                                                     "Macro_case_shape"))))
                        (args ?template ?labels *shape))): {
      List viewed = NULL;
      if (shape)
        viewed = _match_viewed(
          template, labels, shape.car(), binders, frame, finished, pool);
      if (viewed) {
        viewing = 1;
        return viewed;
      }
      List site = x2c_binding_fresh("macro_site");
      List captured = %(call Macro_case_capture_at
        (args (op & $site) $expr $template $labels $buffer));
      return %(block
        (declare (static "MacroCaseSite") (bindings (bind $site ())))
        (if $captured (block @body $finished)));
    }
  if (!((Code) pattern).is_static_pattern()) {
    List captured =
      %(call x2c_match_try_capture (args $expr $boxed $buffer));
    return %(if $captured (block @body $finished));
  }
  List site = x2c_binding_fresh("match_site");
  List captured = %(call x2c_match_site_try_capture
    (args (op & $site) $expr $boxed $buffer));
  return %(block
    (declare (static "MatchCaptureSite") (bindings (bind $site ())))
    (if $captured (block @body $finished)));
}

/* The arm's body, which then breaks unless a guard decides that itself.
   The body stays as the source lowered it, so its own statements, such as
   a nested match, still lower outside this rule. */
meta static List _match_finished(List body) {
  match (body) case %(guarded ?inner): return inner;
  return %(block $body (break));
}

/* The labels that let the switch reach an arm whose pattern value has a
   literal head directly, or NULL. The first arm with a head takes its
   `case`, and later arms with that head are reached by falling through;
   an `!or` of Symbols in the head is each of its Symbols. The first arm
   with no such head can match anything, so it takes `default` and ends
   the labels. */
meta static List _match_labels(Var value, Array heads, int &labelling) {
  if (!labelling) return NULL;
  Symbol head = _match_head(value);
  List alternatives = head ? $(head) : NULL;
  if (!head && value is <list> && value.list())
    match (value.list().car()) case %((!quote !or) *rest): {
      alternatives = rest;
      foreach (Var alternative in rest)
        if (alternative is not <symbol> || alternative.is_binder() ||
            alternative.is_match_op() || alternative == <x2c-dyn>)
          alternatives = NULL;
    }
  if (!alternatives) {
    labelling = 0;
    return %((default));
  }
  Array labels = [];
  foreach (Var alternative in alternatives) {
    if (alternative in heads) continue;
    heads.push(alternative);
    labels.push(%(case $(_match_bits(alternative))));
  }
  return labels.list_free();
}

/* 1 for a directive that opens a conditional group, -1 for one that
   closes it, and 0 for any other. */
meta static int _match_nesting(String text) {
  String directive = text.strip(" \t").remove_prefix("#").strip(" \t");
  if (directive.startswith("endif")) return -1;
  return directive.startswith("if");
}

// the lowering

/* The declarations that read `subject` once as the List `expr`. A `Var`
   subject whose tag is not `<list>` sets `none`. They also declare the
   cursor a macro-valued case starts when one is `viewing`, and the capture
   buffer when an arm captures `values`, the most any such arm captures, or
   -1 when none does. These bind once for the whole match. */
meta static List _match_prologue(
  Code subject, List frame, int viewing, int values) {
  List (expr, none, cursor, capture, buffer) = frame;
  Symbol list = <list>;
  Array declared = [];
  if (subject.type().is_named("Var")) {
    List read = x2c_binding_fresh("match_var");
    List reading = $!{
      Var $read = $subject;
      int $none = !Var_is($read, $list);
      List $expr = Var_list_payload($read);
    };
    declared.push(reading);
  }
  else {
    List converted = subject.convert(%("List"));
    declared.push($!{ List $expr = $converted; });
  }
  if (viewing) declared.push($!{ List $cursor; });
  if (values > 0) {
    List buffered = $!{
      Var $buffer[$values];
      MatchCaptureBuffer $capture = {.values = $buffer, .capacity = $values};
    };
    declared.push(buffered);
  }
  else if (!values) declared.push($!{ MatchCaptureBuffer $capture = {0}; });
  return declared.list_free();
}

/* The arm `arm` behind the check that a `Var` subject is a List. */
meta static List _match_listed(List arm, List none) {
  return %(if (op ! $none) $arm);
}

/* The match of `subject` over `rows`: a block that reads the subject once
   and switches on the bits of its head. A label sits before the
   conditional groups around its arm, so the switch still reaches later
   arms when the preprocessor removes that one. A `Var` subject whose tag
   is not `<list>` is no List: every List arm is skipped, and only a `*`
   arm runs. */
meta static Code _match_lowered(Code subject, List rows) {
  Array items = [], heads = [];
  int labelling = 1, opening = 0, depth = 0, viewing = 0, values = -1;
  int dynamic = subject.type().is_named("Var");
  List frame = _match_frame(subject);
  List (expr, none) = frame;
  Array pool = [];
  foreach (List row in rows) {
    if (row ~= %(preproc ?(String text))) {
      int nesting = _match_nesting(text);
      items.push(row);
      if (nesting > 0 && !depth) opening = items.len() - 1;
      depth += nesting;
      continue;
    }
    List (pattern, body) = row;
    int otherwise = pattern.car() == <*>;
    Var value = otherwise ? %() : ((Code) pattern).pattern_value();
    foreach (List label in _match_labels(value, heads, labelling)) {
      if (depth) items.insert(opening++, label);
      else items.push(label);
    }
    List finished = _match_finished(body);
    List arm =
      otherwise ? finished : _match_arm(pattern, value, expr, finished, pool);
    if (!arm) {
      List binders = _match_binders(value);
      if (binders.len() > values) values = binders.len();
      frame = _match_capturing(frame);
      arm = _match_fallback(pattern, binders, frame, finished, viewing, pool);
    }
    items.push(dynamic && !otherwise ? _match_listed(arm, none) : arm);
  }
  if (labelling) {
    items.push(%(default));
    items.push(%(break));
  }
  List selector = _match_int(0);
  Symbol choose = <"?">;
  if (heads.len())
    selector = %(op $choose $expr (op . (op -> $expr car) u64) $selector);
  List prologue = _match_prologue(subject, frame, viewing, values);
  List switched = Code.lowered(
    %(placed (switch $selector (block @(items.list_free())))), NULL);
  return $!{ { @prologue $switched } };
}

$rewrite($matched)
/** Lowers the bound match `node` to a block around its subject, patterns,
    and bodies.
*/
meta Code match_lowering(Code node) {
  match (node) case $matched(?subject, *rows):
    return _match_lowered(subject, rows);
  return node;
}

/* A pattern condition uses the same tests and fallback as an arm, without
   the switch and implicit break of a match statement. */
meta static Code _match_condition(Code subject, List pattern, List body) {
  int viewing = 0, values = -1;
  List frame = _match_frame(subject);
  List (expr, none) = frame;
  Var value = ((Code) pattern).pattern_value();
  Array pool = [];
  List arm = _match_arm(pattern, value, expr, body, pool);
  if (!arm) {
    List binders = _match_binders(value);
    values = binders.len();
    frame = _match_capturing(frame);
    arm = _match_fallback(pattern, binders, frame, body, viewing, pool);
  }
  if (subject.type().is_named("Var")) arm = _match_listed(arm, none);
  List prologue = _match_prologue(subject, frame, viewing, values);
  List kept = Code.lowered(%(placed $arm), NULL);
  return $!{ { @prologue $kept } };
}

$rewrite(%(match-if *))
/** Lowers a pattern condition through the ordinary match tests. */
meta Code match_condition_lowering(Code node) {
  match (node) case %(match-if ?subject (?pattern ?body)):
    return _match_condition(subject, pattern, body);
  return node;
}
