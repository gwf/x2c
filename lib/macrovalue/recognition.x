/*  recognition.x -- macro value recognition */

/* macro-valued cases

   A `case` that names a macro recognizes code the macro built. A retained
   invocation of the same definition matches by its arguments; other code
   matches the pattern derived from the body, which the case's site keeps
   unless it depends on the current call. */

/** The pattern a macro-valued `case` compiles to; the compiler lowers a
   call of this to `Macro_case_capture_at` over the match subject.
*/
List Macro_case_pattern(Macro t, List names) => Macro_pattern(t, names);

/** The pattern a macro-valued `case` compiles to when the compiler derived
   `shape`, the pattern the case tests, while compiling it. Generated
   `match` code tests `shape` in place through `Macro_case_root` when it
   can, and otherwise lowers a call of this as it lowers
   `Macro_case_pattern`.
*/
List Macro_case_shape(Macro t, List names, List shape) =>
  Macro_pattern(t, names);

/** Recognizes code built by `t` for the `case` whose site is `site`, which
    may be NULL, and publishes the captures under `names`. A pattern that
    does not depend on the current call's subject is prepared once and kept
    in the site; generated `match` code calls this for a macro-valued case.
*/
int Macro_case_capture_at(
  MacroCaseSite *site, List code, Macro t, List names,
  MatchCaptureBuffer *published) {
  List grouped = NULL;
  if (_pending_parts(t, code, grouped))
    return _pending_capture(t, grouped, names, published);
  if (site && __atomic_load_n(&site.ready, __ATOMIC_ACQUIRE))
    return _capture(
      code, site.match.plan, site.policy, site.route, published);
  return _derived_capture(site, code, t, names, published);
}

/** Starts a macro-valued `case` whose derived pattern generated `match`
    code tests in place. Returns 1 when `code` is a retained invocation of
    `t` and its arguments captured under `names` into `published`, 0 when
    `code` cannot match, and 2 after storing in `cursor` the List the
    pattern tests: the view of `code` or, for a `statement` body, of the one
    statement a `seq` holds.
*/
int Macro_case_root(
  List code, Macro t, List names, int statement, List &cursor,
  MatchCaptureBuffer *published) {
  List grouped = NULL;
  Var head = code ? code.car() : NULL;
  /* Only an `expr` shell, an Atom, or a String heads a retained
     invocation, so another Symbol head skips the Atom comparisons. */
  if ((head is not <symbol> || head == <expr>) &&
      _pending_parts(t, code, grouped))
    return _pending_capture(t, grouped, names, published);
  if (!Macro_case_enter(code, cursor)) return 0;
  if (statement && cursor ~= %(seq ?only))
    return Macro_case_enter(only, cursor) ? 2 : 0;
  return 2;
}

/** `Macro_case_enter` for a `value` that may be wrapped or may hold no
    List.
*/
int Macro_case_view(Var value, List &cursor) {
  Var seen = _unwrap(value);
  if (seen is not <list>) return 0;
  cursor = seen;
  return 1;
}

/** Prepares repeated recognition without retaining subject-specific
    bindings.
*/
MacroMatcher Macro.matcher(Macro shape, List holes) {
  Var previous = Macro.subject();
  Macro.use_subject(%());
  defer Macro.use_subject(previous);
  macro_subject_used = 0;
  List pattern = _case_shape(shape, holes);
  return (MacroMatcher){shape, holes, macro_subject_used ? NULL : pattern};
}

/** Tests complete code against a macro and its hole patterns. Repeated
    recognition can retain `Macro.matcher` so the pattern is derived once.
*/
int Macro.matches(Macro t, List code, List holes) {
  MacroMatcher matcher = {t, holes, NULL};
  return matcher.matches(code);
}

/** Tests code with the same source views and identity rules as a macro
    case.
*/
int MacroMatcher.matches(MacroMatcher &m, List code) {
  List pattern =
    m.pattern ? m.pattern : _case_shape(m.shape, m.holes);
  MatchLease lease;
  Symbol status = MatchCache.current().acquire(pattern, lease, "Macro.matches");
  defer lease.release();
  if (status != <prepared>) return 0;
  MatchPlan plan = lease.plan();
  MacroFixedSlots policy = _fixed_slots(m.shape, m.holes, plan);
  return _case_match(code, plan, policy, NULL);
}

/* A retained invocation of this same definition matches by its arguments,
   without expanding it. Each form is its own case, so every macro-valued
   case tests them in place. */
static int _pending_parts(Macro t, List code, List &grouped) {
  match (code) {
    case %(macro-invoke ?descriptor (args *rows) ?):
      return _invoked_parts(t, descriptor, rows, grouped);
    case %(expr ? (macro-invoke ?descriptor (args *rows) ?)):
      return _invoked_parts(t, descriptor, rows, grouped);
    case %("x2c.template" ?descriptor ?arguments): {
      if (!_same(t, descriptor)) return 0;
      grouped = arguments;
      return 1;
    }
  }
  return 0;
}

// The arguments of a `macro-invoke` of this same definition.
static int _invoked_parts(
  Macro t, Var descriptor, List rows, List &grouped) {
  if (!_same(t, descriptor)) return 0;
  grouped = _invoke_values(t, rows);
  return 1;
}

/* A retained invocation may name its macro, carry its stored definition,
   or carry this value; a definition is identified by its name and the
   place it was written. */
static int _same(Macro t, Var descriptor) {
  if (descriptor.is_atom()) return descriptor.str() == t.assoc(<name>).str();
  if (descriptor is not <list>) return 0;
  List stored = descriptor;
  return List.compare(stored, t) == 0 ||
    (stored.car() == <macrodef> &&
     stored.assoc(<name>).str() == t.assoc(<name>).str() &&
     List.compare(stored.assoc(<origin>), t.assoc(<origin>)) == 0);
}

/* The arguments a `macro-invoke` recorded, one per parameter: the bound
   expression of an expression parameter, the value of any other, and the
   captured items of a sequence. */
static List _invoke_values(Macro t, List rows) {
  Array projected = [];
  List holes = t.assoc(<parameters>);
  foreach (List row in rows) {
    List hole = holes.car();
    holes = holes.cdr();
    Var value = hole.assoc(<kind>) == <expr>
      ? row.assoc(<expression>) : row.assoc(<value>);
    if (hole.assoc(<sequence>).int() &&
        row ~= %(capture ? (value *items) *)) value = items;
    projected.push(value);
  }
  return projected.list_free();
}

/* Matches a retained invocation's arguments, one per parameter, against
   the parameters' binders. */
static int _pending_capture(
  Macro t, List grouped, List names, MatchCaptureBuffer *published) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captured = {values, 0, MACHINE_BINDER_MAX};
  List internal = _internal_names(t, names, 1);
  if (!x2c_match_try_capture(grouped, internal, captured)) return 0;
  MacroPublishing route = _publishing(t, internal, names, internal);
  return _publish(route, captured, published);
}

/* Derives the pattern for this call. `site` keeps a pattern that does not
   depend on the call's subject; any other is prepared for this call
   alone. */
static int _derived_capture(
  MacroCaseSite *site, List code, Macro t, List names,
  MatchCaptureBuffer *published) {
  macro_subject_used = 0;
  List pattern = _case_shape(t, names);
  MacroPublishing route = _publishing(
    t, pattern, names, _internal_names(t, names, 0));
  if (_keep(site, t, names, pattern, route))
    return _capture(
      code, site.match.plan, site.policy, site.route, published);
  MatchPlan plan = MatchPlan.prepare(pattern);
  defer plan.free();
  MacroFixedSlots policy = _fixed_slots(t, names, plan);
  return _capture(code, plan, policy, route, published);
}

/* The binder each parameter is captured under inside the derived pattern:
   a Type parameter is a List splice, so it needs a List binder. Against a
   retained invocation each binder captures one argument. */
static List _internal_names(Macro t, List names, int pending) {
  Array internal = [];
  foreach (List hole in t.assoc(<parameters>).list()) {
    String label = names.car().str(), prefix = label[0:1];
    names = names.cdr();
    if (pending) prefix = "?";
    else if (hole.assoc(<kind>) == <type>) prefix = "*";
    internal.push(Atom.intern(prefix + label[1:]));
  }
  return internal.list_free();
}

static int _capture(
  List code, MatchPlan plan, MacroFixedSlots &policy, MacroPublishing &route,
  MatchCaptureBuffer *published) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captured = {values, 0, MACHINE_BINDER_MAX};
  return _case_match(code, plan, policy, captured) &&
    _publish(route, captured, published);
}

/* Keeps `pattern` in `site` with its fixed slots and route once Match
   retains its prepared plan, unless the pattern resolved a reference
   against the current call's subject. Returns whether `site` is ready. */
static int _keep(
  MacroCaseSite *site, Macro t, List names, List pattern,
  MacroPublishing &route) {
  MatchPlan kept = site && !macro_subject_used && List.try_own(pattern)
                 ? x2c_match_site_prepare(&site.match, pattern) : NULL;
  if (!kept || kept.status != <prepared>) return 0;
  site.policy = _fixed_slots(t, names, kept);
  site.route = route;
  __atomic_store_n(&site.ready, 1, __ATOMIC_RELEASE);
  return 1;
}

/* recognition with binding hygiene

   Declarations the body introduces match any identity in the subject, one
   distinct identity per declaration; other references match the subject's
   binding of the same spelling. Source wrappers are removed from both
   sides for comparison, while captured values keep the subject's original
   subtrees. */

/* The pattern a case runs: each fixed local bound to one distinct
   identity, a statement sequence that also matches as a block, and no
   source wrappers. */
static List _case_shape(Macro t, List names) {
  List pattern = _pattern(t, names, 1), replacements = NULL;
  int ordinal = 0;
  foreach (List fresh in t.assoc(<fresh>).list()) {
    Atom identity = _fixed(ordinal++);
    replacements = cons(
      %($(fresh.car()) (binding (!and $identity $identity) ?)),
      replacements);
  }
  pattern = pattern.replace(replacements);
  /* A Unit body that is one function definition recognizes that bound
     function, which carries no `api-source` record. */
  match (pattern) {
    case %(seq *parts): pattern = %(!or (seq @parts) (block @parts));
    case %(api-source ? ? ?function): pattern = function;
  }
  return _view(pattern);
}

/* Removes source wrappers and template shells throughout a pattern, down
   to literals and bindings, which stay whole. */
static Var _view(Var value) {
  value = _unwrap(value);
  if (value is not <list>) return value;
  List node = value;
  match (node) {
    case %(literal *): return value;
    case %(binding ? ?): return value;
  }
  Array parts = [];
  foreach (Var child in node) parts.push(_view(child));
  return parts.list_free();
}

// Records fixed-local and Name slots in the prepared plan.
static MacroFixedSlots _fixed_slots(
  Macro t, List names, MatchPlan plan) {
  MacroFixedSlots policy;
  policy.count = policy.names = 0;
  if (plan.status != <prepared>) return policy;
  int ordinal = 0;
  foreach (List fresh in t.assoc(<fresh>).list()) {
    int slot = plan.layout.index(_fixed(ordinal++));
    if (slot >= 0) policy.slots[policy.count++] = slot;
  }
  foreach (List hole in t.assoc(<parameters>).list()) {
    if (hole.assoc(<kind>) == <name>) {
      int slot = plan.layout.index(names.car());
      if (slot >= 0) policy.name_slots[policy.names++] = slot;
    }
    names = names.cdr();
  }
  return policy;
}

// Declaration order gives each body-local binder its identity.
static Atom _fixed(int index) => Atom.intern(%"?__fixed_$index");

/* Runs `plan` over `code` with the fixed-local relation and the unwrapping
   view, and copies captures when requested. An unprepared plan takes Match's
   ordinary route, which reports why. */
static int _case_match(
  List code, MatchPlan plan, MacroFixedSlots &policy,
  MatchCaptureBuffer &?captured) {
  if (plan.status != <prepared>)
    return plan.execute_capture(code, captured, NULL) == 1;
  if (!plan.admits(code, _unwrap)) return 0;
  MatchMachine machine;
  machine.open();
  machine.relation = _identity_equal;
  machine.relation_context = &policy;
  machine.view = _unwrap;
  machine.begin(plan.program.view(), code);
  machine.run();
  int matched = machine.status == <ok> &&
    (!captured || _take_slots(machine, captured));
  machine.finish();
  machine.dispose();
  return matched;
}

/* Copies each slot the machine filled, materializing spans, and returns
   whether the machine is still ok. */
static int _take_slots(
  MatchMachine &machine, MatchCaptureBuffer &captured) {
  for (int i = 0; i < machine.slot_count; i++) {
    MachineSlot *slot = &machine.slots[i];
    if (slot.kind == <invalid>) continue;
    captured.values[i] = slot.kind == <span>
      ? machine.materialize_span(slot.span) : slot.value;
    captured.present |= 1UL << i;
  }
  return machine.status == <ok>;
}

/* A repeated binder compares the nodes both sides unwrap to. At a fixed
   local's slot, a node another fixed local already holds is unequal, so
   distinct declarations capture distinct identities. */
static int _identity_equal(
  void *raw_machine, int slot, Var left, Var right, void *raw_policy) {
  MatchMachine *machine = raw_machine;
  MacroFixedSlots *policy = raw_policy;
  left = _unwrap(left);
  right = _unwrap(right);
  if (_has_slot(policy.name_slots, policy.names, slot)) {
    String spelling = NULL;
    if (left is <string> && right is <list>)
      spelling = _source_spelling(right);
    else if (right is <string> && left is <list>)
      spelling = _source_spelling(left);
    if (spelling) return spelling == (left is <string> ? left : right);
  }
  if (!left.equal(right)) return 0;
  if (!_has_slot(policy.slots, policy.count, slot)) return 1;
  return !_held_elsewhere(*machine, policy, slot, right);
}

static int _has_slot(const int *slots, int count, int slot) {
  for (int i = 0; i < count; i++) if (slots[i] == slot) return 1;
  return 0;
}

/* The caller's source spelling survives helper transport in the existing
   subject rows; ordinary bindings use the spelling they already carry. */
static String _source_spelling(List value) {
  foreach (List row in macro_subject is <list> ? macro_subject.list() : NULL)
    if (row ~= %(source-spelling ?binding ?(String spelling)) &&
        List.compare(binding, value) == 0) return spelling;
  if (value ~= %(binding ? ?(String spelling))) return spelling;
  return NULL;
}

// Whether a fixed local's slot other than `slot` holds `value`.
static int _held_elsewhere(
  MatchMachine &machine, MacroFixedSlots *policy, int slot, Var value) {
  for (int i = 0; i < policy.count; i++) {
    int other = policy.slots[i];
    if (other != slot && machine.slots[other].kind == <value> &&
        machine.slots[other].value.equal(value))
      return 1;
  }
  return 0;
}

/* The node a pattern examines for `value`: through position and source
   wrappers, and through the shell binding leaves around a typed
   expression. */
static Var _unwrap(Var value) {
  for (;;) {
    if (value is not <list>) return value;
    List node = value;
    match (node) {
      case %(at ? ?body): value = body;
      case %(src ? ?body): value = body;
      case %(expr (<macro-expr>) ?inner): {
        // Both expression tests stay in place on this hot path.
        if (inner ~= %(expr *)) {
          value = inner;
          continue;
        }
        return value;
      }
      default: return value;
    }
  }
}

/* publishing captures

   A pattern captures each parameter under an internal binder. Publishing
   copies those captures into the slots of the `case`'s own binders. */

/* Where each of the user's binders reads its capture: the slot of its
   internal binder in `pattern` and its own slot among `names`. A binder
   either side lacks leaves the route incomplete. */
static MacroPublishing _publishing(
  Macro t, List pattern, List names, List internal) {
  MacroPublishing route = {.complete = 1};
  MatchCaptureLayout actual = MatchCaptureLayout.analyze(pattern);
  MatchCaptureLayout logical = MatchCaptureLayout.analyze(names);
  List holes = t.assoc(<parameters>);
  for (; names; names = names.cdr(), internal = internal.cdr(),
                  holes = holes.cdr()) {
    int fallback = actual.index(internal.car());
    int from = holes.car().list().assoc(<kind>) == <name>
             ? actual.index(_name_identity(holes.car())) : -1;
    if (from < 0) from = fallback;
    int to = logical.index(names.car());
    if (from < 0 || to < 0) route.complete = 0;
    route.from[route.count] = from;
    route.fallback[route.count] = fallback;
    route.to[route.count++] = to;
  }
  route.binders = logical.binder_count;
  route.definite = logical.definite;
  actual.free();
  logical.free();
  return route;
}

/* Publishes the internal captures under the user's binders. An incomplete
   route or an absent capture publishes nothing and returns 0. */
static int _publish(
  MacroPublishing &route, MatchCaptureBuffer &captured,
  MatchCaptureBuffer *published) {
  if (!route.complete) return 0;
  Var ordered[MACHINE_BINDER_MAX];
  for (int i = 0; i < route.count; i++) {
    int from = captured.has(route.from[i])
             ? route.from[i] : route.fallback[i];
    if (from < 0 || !captured.has(from)) return 0;
    ordered[route.to[i]] = captured.values[from];
  }
  for (int i = 0; i < route.binders; i++) published.values[i] = ordered[i];
  published.present = route.definite;
  return 1;
}
