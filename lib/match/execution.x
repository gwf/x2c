/*  execution.x -- prepared-plan execution and capture publication */

/* plan execution

   Only a prepared plan runs. An entry point raises the fence of an
   ineligible plan, and a malformed plan answers no match. */

/** Raises the fence an ineligible plan crossed, naming `owner`.
    This is the one place an ineligible pattern is reported. Such a pattern
    compiles to no program, so answering "no match" would be wrong and no
    caller could tell it from a real miss. `reason` is the plan's static
    category string.
    Raises: `<size-limit>` with `operation` and the fence.
*/
void MatchPlan.raise_ineligible(const char *reason, const char *owner) {
  String fence = String.new(reason), site = String.new(owner);
  raise %(size-limit (operation $site) (fence $fence));
}

/* Entry-point guard over an already prepared plan; `plan` stays owned by
   its caller. Malformed patterns keep their categorized no-match. */
module int _prepared(MatchPlan plan, const char *owner) {
  if (plan && plan.status == <ineligible>)
    MatchPlan.raise_ineligible(plan.reason, owner);
  return plan && plan.status == <prepared>;
}

module int _buffer_valid(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures) {
  if (!layout || !captures) return 0;
  if (captures.capacity < layout.binder_count) return 0;
  return !layout.binder_count || captures.values != NULL;
}

/* Declares `$instance`, an open machine of this thread. */
static macro Stmt $match.machine(Name $instance, Expr $stats) {
  MatchMachine *$instance = MatchMachine.acquire($stats);
}

/** Executes a prepared plan into caller-owned positional storage.
    Returns 1 on a match, 0 on a miss, and -1 for a null or malformed plan, an
    invalid buffer, or a machine error. Only success replaces `present` and
    the indicated values; all other results leave the buffer unchanged.
    `stats`, when nonnull, receives increments and is not initialized here.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    materializing captures.
*/
int MatchPlan.execute_capture(
  MatchPlan m, Var input, MatchCaptureBuffer &?captures,
  MachineStats &?stats) {
  if (!_prepared(m, "MatchPlan.execute_capture") ||
      !_buffer_valid(m.layout, captures))
    return -1;
  return _capture(m, input, captures, stats);
}

/** Executes a prepared `List` match into caller-owned positional storage.
    This is `MatchPlan.execute_capture` without statistics and has the same
    results, atomicity, and failures.
*/
int MatchPlan.try_capture(
  MatchPlan plan, List input, MatchCaptureBuffer &?captures) =>
    plan.execute_capture(input, captures, NULL);

module int _capture(
  MatchPlan m, Var input, MatchCaptureBuffer *captures, MachineStats *stats) {
  if (!m.admits(input, NULL)) return 0;
  $match.machine(machine, stats);
  int result = _run_capture(m.program.view(), *machine, input, captures);
  machine.release();
  return result;
}

/** Reports whether `input`, seen through `view` when one is given, begins
    as one of the keys of prepared `plan` requires. A plan without keys
    admits every input, and a refused input is one the plan cannot match.
*/
int MatchPlan.admits(MatchPlan plan, Var input, Var (*view)(Var)) {
  if (!plan.key_count) return 1;
  List list = _seen_list(input, view);
  if (!list) return 0;
  for (int i = 0; i < plan.key_count; i++)
    if (_key_admits(plan, &plan.keys[i], list, view)) return 1;
  return 0;
}

/* The nonempty List `view` shows for `value`, or NULL. */
static List _seen_list(Var value, Var (*view)(Var)) {
  if (view) value = view(value);
  return value is <list> ? value.list() : NULL;
}

static int _key_admits(
  MatchPlan plan, MatchKey *key, List list, Var (*view)(Var)) {
  if (!_key_equal(plan, list.car(), key.head)) return 0;
  if (!key.index) return 1;
  for (int i = 0; i < key.index && list; i++) list = list.cdr();
  if (!list) return 0;
  Var element = list.car();
  if (key.nested) {
    List inner = _seen_list(element, view);
    if (!inner) return 0;
    element = inner.car();
  }
  return _key_equal(plan, element, key.inner);
}

static int _key_equal(MatchPlan plan, Var value, Var key) =>
  plan.key_bits ? value.u64 == key.u64 : value.equal(key);

/* Runs one prepared execution and commits positional values only after the
   machine and every lazy-span materialization have succeeded. */
module int _run_capture(
  MachineView view, MatchMachine &m, Var input, MatchCaptureBuffer *captures) {
  if (!captures || captures.capacity < view.binder_count ||
      (view.binder_count && !captures.values))
    return -1;
  m.begin(view, input);
  m.run();
  int result = -1;
  if (m.status == <ok>) result = _commit(view, m, captures);
  else if (m.status == <fail>) result = 0;
  m.finish();
  return result;
}

/* Materializes each captured span, then commits every present value at
   once; a failed materialization leaves the buffer unchanged. */
static int _commit(
  MachineView view, MatchMachine &m, MatchCaptureBuffer *captures) {
  Var values[MACHINE_BINDER_MAX];
  unsigned long present = 0;
  for (int i = 0; i < view.binder_count; i++) {
    MachineSlot *slot = &m.slots[i];
    if (slot.kind == <invalid>) continue;
    values[i] = slot.value;
    if (slot.kind == <span>)
      values[i] = m.materialize_span(slot.span);
    if (m.status == <error>) break;
    present |= 1UL << i;
  }
  if (m.status != <ok>) return -1;
  captures.present = present;
  for (int i = 0; i < view.binder_count; i++)
    if (_capture_bit(present, i)) captures.values[i] = values[i];
  return 1;
}

/** Executes `plan` against `input` and publishes association bindings.
    Returns 1 and writes `out_bindings` on a match, 0 on a miss, and -1 for a
    null or malformed plan, null output, or machine error. Failure leaves the
    output unchanged. A binder-free success writes `nil`; other bindings are in
    reverse canonical slot order. `stats`, when nonnull, receives increments
    and is not initialized here.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    materializing or publishing bindings.
*/
int MatchPlan.execute(
  MatchPlan plan, Var input, List &?out_bindings, MachineStats &?stats) {
  if (!_prepared(plan, "MatchPlan.execute")) return -1;
  if (!out_bindings) return -1;
  if (!plan.admits(input, NULL)) return 0;
  $match.machine(machine, stats);
  List bindings, int result = _run(plan, *machine, input, bindings);
  machine.release();
  if (result == 1) out_bindings = bindings;
  return result;
}

/** Executes prepared `plan` against `input`, writing bindings on success.
    This is `MatchPlan.execute` without statistics and has the same status,
    output atomicity, ordering, and failures.
*/
int MatchPlan.try_match(MatchPlan plan, List input, List &?out_bindings) =>
  plan.execute(input, out_bindings, NULL);

/* Publication reads committed positional state, never speculative matcher
   state. */
static int _run(
  MatchPlan mm, MatchMachine &m, Var input, List &out) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = { values, 0, MACHINE_BINDER_MAX };
  int result = _run_capture(mm.program.view(), m, input, &captures);
  if (result == 1) out = _publish_captures(mm.layout, &captures);
  return result;
}

/* The committed captures as an association List in reverse slot order. */
module List _publish_captures(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures) {
  List bindings = NULL;
  for (int i = 0; i < layout.binder_count; i++) {
    if (!_capture_bit(captures.present, i)) continue;
    List pair = $(layout.binders[i], captures.values[i]);
    bindings = cons(pair, bindings);
  }
  return bindings;
}
