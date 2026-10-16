/*  traversal.x -- first-match, all-match and replacement walks */

/* searches

   A search visits a List's head, then its tail, then the List itself. An
   explicit `nil` element is a node, but a proper List's terminal cdr is
   traversal structure and is never tested. */

/* One prepared walk borrows a plan, machine, and capture buffer, and owns
   the cell stack its cdr loops share. Each level takes the region above the
   length it found and restores that length before returning, so one growing
   allocation serves the whole traversal. The first-match walk writes
   `found` and `bindings`, the search walk `results`, and the replacing walk
   reads `template` and sets `error`. */
static typedef struct MatchWalk {
  MatchPlan plan;
  MachineView view;
  MatchCaptureBuffer *captures;
  MatchMachine *m;
  Block spine;
  Var found, template;
  List bindings, results;
  int error;
} MatchWalk;

/* Declares `$walk` over `$plan` and `$machine` with its own capture buffer
   and an empty cell stack. */
static macro Stmt $match.walk(
  Type $walk_type, Expr $plan, Expr $machine, Name $walk) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = { values, 0, MACHINE_BINDER_MAX };
  $walk_type $walk = {
    $plan, ($plan).program.view(), &captures, $machine,
    Block.new(sizeof(Var))
  };
}

/** Searches `input` with `plan`, writing the first match and bindings.
    Traversal is depth-first head, tail, then containing `List`. Returns 1 on a
    match, 0 on a miss, and -1 for an unusable plan, invalid outputs, or a
    machine error. Unless it returns 1, both outputs remain unchanged.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    materializing or publishing bindings.
*/
int MatchPlan.try_search(
  MatchPlan plan, List input, Var &?out_match, List &?out_bindings) {
  if (!_prepared(plan, "MatchPlan.try_search") || !out_match ||
      !out_bindings)
    return -1;
  return _first(plan, input, out_match, out_bindings);
}

static int _first(
  MatchPlan plan, List input, Var &out_match, List &out_bindings) {
  $match.machine(machine, NULL);
  $match.walk(MatchWalk, plan, machine, walk);
  int result = _walk_first(walk, input, 1);
  walk.spine.free();
  machine.release();
  if (result == 1) {
    out_match = walk.found;
    out_bindings = walk.bindings;
  }
  return result;
}

/** Writes all matches of `plan` within `input` to `out_results`.
    Each result has the shape documented by `List.search` and the completed
    `List` is in reverse visitation order. Returns 1 after a complete
    traversal, including when it writes `nil` for no matches; returns -1 and
    leaves the output unchanged for an unusable plan, null output, or machine
    error.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    constructing results.
*/
int MatchPlan.search(MatchPlan plan, List input, List &?out_results) {
  if (!_prepared(plan, "MatchPlan.search") || !out_results) return -1;
  return _all(plan, input, out_results);
}

static int _all(MatchPlan plan, List input, List &out_results) {
  $match.machine(machine, NULL);
  $match.walk(MatchWalk, plan, machine, walk);
  int status = _walk_all(walk, input, 1);
  walk.spine.free();
  machine.release();
  if (status < 0) return -1;
  out_results = walk.results;
  return 1;
}

/** Replaces every match of `plan` from the leaves upward.
    Returns 1 and writes the completed `List` even when nothing matched.
    Returns -1 and leaves `out` unchanged for an unusable plan, null output,
    or machine error. Children are replaced before their containing `List` is
    tested.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    traversing or replacing.
*/
int MatchPlan.search_replace(
  MatchPlan plan, List input, Var template, List &?out) {
  if (!_prepared(plan, "MatchPlan.search_replace") || !out) return -1;
  return _replace_all(plan, input, template, out);
}

static int _replace_all(
  MatchPlan plan, List input, Var template, List &out) {
  $match.machine(machine, NULL);
  $match.walk(MatchWalk, plan, machine, walk);
  walk.template = template;
  Var result = _rewrite(walk, input, 1);
  walk.spine.free();
  machine.release();
  if (walk.error) return -1;
  out = result;
  return 1;
}

/* walks

   A walk runs the plan at each node of one traversal, sharing one machine,
   one capture buffer, and one cell stack. */

static int _test(MatchWalk &m, Var node) =>
  m.plan.admits(node, NULL)
    ? _run_capture(m.view, *m.m, node, m.captures) : 0;

/* One search result: `(* node)` followed by the node's bindings. */
static List _hit(MatchWalk &walk, Var node) =>
  cons(%(* $node), _publish_captures(walk.plan.layout, walk.captures));

static Var _spine_get(Block spine, size_t index) =>
  ((Var *) spine.bytes)[index];

/* Every traversal descends car with include_empty=1 and cdr with
   include_empty=0 before trying the match at this node. The cdr descent runs
   as a loop, so a `List` of any length costs one frame and only nesting
   depth reaches the C stack. The loop visits every car in order and then
   answers for the cells from the last one back, which is the order the
   recursion produced. */
static int _walk_all(MatchWalk &walk, Var input, int include_empty) {
  Block hits = walk.spine;
  size_t base = hits.length;
  int visit_tail = 1;
  while (input is <list>) {
    List lst = input;
    if (!lst) {
      visit_tail = include_empty;
      break;
    }
    if (_walk_all(walk, lst.car(), 1) < 0) return -1;
    int status = _test(walk, input);
    if (status < 0) return -1;
    if (status == 1) {
      Var hit = _hit(walk, input);
      hits.push(&hit);
    }
    input = lst.cdr();
    include_empty = 0;
  }
  if (visit_tail) {
    int status = _test(walk, input);
    if (status < 0) return -1;
    if (status == 1) walk.results = cons(_hit(walk, input), walk.results);
  }
  _answer(walk, base);
  return 0;
}

/* Prepends the hits the loop pushed above `base`, last one first, as the
   recursion answered them, and releases them. */
static void _answer(MatchWalk &walk, size_t base) {
  Block hits = walk.spine;
  for (size_t i = hits.length; i > base; i--)
    walk.results = cons(_spine_get(hits, i - 1), walk.results);
  hits.truncate(base);
}

/* The cells answer from the last one back, so the walk remembers the last
   cell that matched and settles on it once nothing earlier matches. */
static int _walk_first(MatchWalk &walk, Var input, int include_empty) {
  Var last_cell = void;
  int have_cell = 0, visit_tail = 1;
  while (input is <list>) {
    List lst = input;
    if (!lst) {
      visit_tail = include_empty;
      break;
    }
    int found = _walk_first(walk, lst.car(), 1);
    if (found) return found;
    int status = _test(walk, input);
    if (status < 0) return -1;
    if (status == 1) {
      last_cell = input;
      have_cell = 1;
    }
    input = lst.cdr();
    include_empty = 0;
  }
  if (visit_tail) {
    int status = _settle(walk, input);
    if (status) return status;
  }
  // the buffer now holds a later node, so the winner runs once more
  return have_cell ? _settle(walk, last_cell) : 0;
}

/* Tests `node` and, when it matches, publishes it with its bindings. */
static int _settle(MatchWalk &walk, Var node) {
  int status = _test(walk, node);
  if (status != 1) return status;
  walk.found = node;
  walk.bindings = _publish_captures(walk.plan.layout, walk.captures);
  return 1;
}

/* Rewrites children before the List that holds them. The loop pushes each
   rewritten car; the cells then rebuild from the last one back, each around
   the tail so far. */
static Var _rewrite(MatchWalk &walk, Var node, int include_empty) {
  Block heads = walk.spine;
  size_t base = heads.length;
  int visit_tail = 1;
  while (node is <list>) {
    List lst = node;
    if (!lst) {
      visit_tail = include_empty;
      break;
    }
    Var head = _rewrite(walk, lst.car(), 1);
    if (walk.error) return node;
    heads.push(&head);
    node = lst.cdr();
    include_empty = 0;
  }
  if (visit_tail) node = _replace_node(walk, node);
  for (size_t i = heads.length; i > base && !walk.error; i--) {
    List tail = node;
    node = _replace_node(walk, cons(_spine_get(heads, i - 1), tail));
  }
  heads.truncate(base);
  return node;
}

/* The instantiated template when `node` matches, or else `node`. */
static Var _replace_node(MatchWalk &walk, Var node) {
  int status = _test(walk, node);
  if (status < 0) {
    walk.error = 1;
    return node;
  }
  if (status == 0) return node;
  ReplacementSource source = { walk.plan.layout, walk.captures, NULL };
  return _replace(walk.template, source);
}
