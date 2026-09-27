#include "meta.x"
#include <assert.h>

// Side ownership maps are supplied by the existing parser/binder interface.
// The returned projection is comparison data; insertion uses original syntax.
static Var compare_view(Var value, Map owned, Map boundary) {
  if (value is not <list>) return value;
  List node = value;
  match (node) case %(binding ?id ?label): {
    Var slot;
    if (owned.try_get(id, slot)) return %(local $slot);
    if (boundary.try_get(id, slot)) return %(boundary $slot);
    return %(free $id);
  }
  Array items = [];
  foreach (Var child, node) items.push(compare_view(child, owned, boundary));
  return items.list_free();
}

// All capture rows share a relocation map. No per-hole isolated freshening.
static Var relocate(Var value, Map identities) {
  if (value is not <list>) return value;
  List node = value;
  match (node) case %(binding ?id ?label): {
    Var replacement;
    return identities.try_get(id, replacement) ? replacement : value;
  }
  Array items = [];
  foreach (Var child, node) items.push(relocate(child, identities));
  return items.list_free();
}

static List instantiate(List body, List rows, Map identities) =>
  body.replace(relocate(rows, identities));

static int recognize(List body, List syntax, List &rows) =>
  syntax.try_match(body, rows);

static int alpha_equal(List a, Map a_owned, Map a_boundary,
                       List b, Map b_owned, Map b_boundary) {
  List av = compare_view(a, a_owned, a_boundary);
  List bv = compare_view(b, b_owned, b_boundary);
  return av.compare(bv) == 0;
}

static void arithmetic(void) {
  List body = %(expr () (op + ?left ?right));
  List source = %(expr () (op + (expr () (ident (binding 80 "price")))
                                (expr () (ident (binding 81 "tax")))));
  List rows;
  assert(recognize(body, source, rows));
  assert(instantiate(body, rows, {}).compare(source) == 0);
  assert(!recognize(body, %(expr () (op - A B)), rows));
  List twice = %(expr () (op + ?same ?same));
  assert(recognize(twice, %(expr () (op + A A)), rows));
  assert(!recognize(twice, %(expr () (op + A B)), rows));
  List call = %(expr () (call ?callee (args *items)));
  List many = %(expr () (call F (args A B C))), none = %(expr () (call F (args)));
  assert(recognize(call, many, rows));
  assert(instantiate(call, rows, {}).compare(many) == 0);
  assert(recognize(call, none, rows));
  assert(instantiate(call, rows, {}).compare(none) == 0);
  // Composition substitutes an existing structural body, rather than authoring
  // a second recognition pattern for the composed shape.
  List outer = %(expr () (parens ?inside));
  List composed = outer.replace(%((?inside $body)));
  List wrapped = %(expr () (parens $source));
  assert(recognize(composed, wrapped, rows));
  assert(instantiate(composed, rows, {}).compare(wrapped) == 0);
}

static void scope_relations(void) {
  List left = %(block
    (declare (int) (bindings (bind (binding 1 "x") ())))
    (block (declare (int) (bindings (bind (binding 2 "x") ())))
           (stmnt (expr () (ident (binding 2 "x")))))
    (stmnt (expr () (ident (binding 1 "x"))))
    (stmnt (expr () (ident (binding 10 "external")))));
  Map left_owned = {}, right_owned = {};
  left_owned[1] = 0; left_owned[2] = 1;
  right_owned[4] = 0; right_owned[5] = 1;
  Map renamed = {};
  renamed[1] = %(binding 4 "outer"); renamed[2] = %(binding 5 "inner");
  List right = relocate(left, renamed);
  assert(alpha_equal(left, left_owned, {}, right, right_owned, {}));
  Map wrong_shadow = {};
  wrong_shadow[5] = %(binding 4 "outer");
  List wrong = relocate(right, wrong_shadow);
  assert(!alpha_equal(left, left_owned, {}, wrong, right_owned, {}));
  Map wrong_free = {}; wrong_free[10] = %(binding 11 "external");
  wrong = relocate(right, wrong_free);
  assert(!alpha_equal(left, left_owned, {}, wrong, right_owned, {}));
  // A contextual capture refers to surrounding slot zero while preserving free 10.
  Map a_boundary = {}, b_boundary = {};
  a_boundary[1] = 0; b_boundary[4] = 0;
  assert(alpha_equal(%(expr () (ident (binding 1 "x"))), {}, a_boundary,
                     %(expr () (ident (binding 4 "outer"))), {}, b_boundary));
  assert(!alpha_equal(%(expr () (ident (binding 1 "x"))), {}, {},
                      %(expr () (ident (binding 4 "outer"))), {}, {}));
}

static void joint_relocation(void) {
  List body = %(block *prefix (return () ?value));
  List source = %(block
    (declare (int) (bindings (bind (binding 30 "x") ())))
    (return () (expr () (ident (binding 30 "x")))));
  List rows;
  assert(recognize(body, source, rows));
  Map fresh = {}; fresh[30] = %(binding 40 "new_x");
  List output = instantiate(body, rows, fresh);
  List expected = %(block
    (declare (int) (bindings (bind (binding 40 "new_x") ())))
    (return () (expr () (ident (binding 40 "new_x")))));
  assert(output.compare(expected) == 0);
  // Repeated copies need per-insertion correspondence, not one global remap.
  List region = %(block (declare (int) (bindings (bind (binding 30 "x") ())))
                       (return () (expr () (ident (binding 30 "x")))));
  Map first = {}, second = {};
  first[30] = %(binding 41 "one"); second[30] = %(binding 42 "two");
  List one = relocate(region, first), two = relocate(region, second);
  assert(one.compare(two) != 0);
  Map a_owned = {}, b_owned = {}; a_owned[41] = 0; b_owned[42] = 0;
  assert(alpha_equal(one, a_owned, {}, two, b_owned, {}));
}

static void closed_sequence_retry(void) {
  // The body and occurrence captures use ordinary Match. Comparison projection
  // enables repeated closed-hole alpha equality inside actual machine retries.
  List closed_a = %(block (declare (int) (bindings (bind (binding 50 "a") ())))
                          (return () (expr () (ident (binding 50 "a")))));
  List different = %(block (declare (int) (bindings (bind (binding 51 "b") ())))
                           (return () (expr () (ident (binding 90 "free")))));
  List closed_a2 = %(block (declare (int) (bindings (bind (binding 52 "c") ())))
                           (return () (expr () (ident (binding 52 "c")))));
  Map a = {}, b = {}, c = {}; a[50] = 0; b[51] = 0; c[52] = 0;
  Var av = compare_view(closed_a, a, {}), bv = compare_view(different, b, {});
  Var cv = compare_view(closed_a2, c, {});
  List projected = %($av $bv $cv), rows;
  assert(projected.try_match(%(?same *between ?same *tail), rows));
  assert(rows.assoc(<*between>).list().len() == 1);
  assert(rows.assoc(<*tail>).list().len() == 0);
  assert(!%($av $bv).try_match(%(?same *between ?same *tail), rows));
}

static int core_checks(void) {
  arithmetic(); scope_relations(); joint_relocation(); closed_sequence_retry();
  puts("core: shared body, sequences, composition, alpha scopes, joint relocation, closed contextual retry PASS");
  return 0;
}

// Immutable contextual policy reads the machine's transactional fixed-local
// slot. It creates temporary comparison views; no independent search engine.
typedef struct RelationContext {
  int local_slot, same_slot, calls, rejected;
  Map owned;
} RelationContext;

static Map owned_for(Var value, Map owners) {
  Var found;
  if (owners.try_get(value, found)) return found;
  Map merged = {};
  if (value is <list>) foreach (Var child, value.list())
    merged.merge(owned_for(child, owners));
  return merged;
}

static int contextual_equal(void *raw_machine, int slot, Var left, Var right,
                            void *raw_context) {
  MatchMachine machine = raw_machine;
  RelationContext *context = raw_context;
  if (slot != context.same_slot) return left == right;
  context.calls++;
  Var local = machine.slots[context.local_slot].value;
  Map boundary = {}; boundary[local] = 0;
  Map left_owned = owned_for(left, context.owned);
  Map right_owned = owned_for(right, context.owned);
  int same = alpha_equal(left, left_owned, boundary,
                         right, right_owned, boundary);
  if (!same) context.rejected++;
  return same;
}

static void contextual_sequence_retry(void) {
  List first = %(block
    (declare (int) (bindings (bind (binding 50 "a") ())))
    (return () (expr () (op + (ident (binding 50 "a"))
                           (ident (binding 30 "surrounding"))))));
  List wrong = %(block
    (declare (int) (bindings (bind (binding 51 "b") ())))
    (return () (expr () (op + (ident (binding 51 "b"))
                           (ident (binding 31 "surrounding"))))));
  List later = %(block
    (declare (int) (bindings (bind (binding 52 "c") ())))
    (return () (expr () (op + (ident (binding 52 "c"))
                           (ident (binding 30 "renamed-label"))))));
  List pattern = %(block
    (declare (int) (bindings (bind (binding ?local ?) ())))
    ?same *between ?same *tail);
  List subject = %(block
    (declare (int) (bindings (bind (binding 30 "outer") ())))
    $first $wrong $later);
  MatchPlan plan = MatchPlan.prepare(pattern);
  RelationContext context;
  context.local_slot = plan.layout.index(<?local>);
  context.same_slot = plan.layout.index(<?same>);
  context.calls = 0; context.rejected = 0; context.owned = {};
  Map a = {}, b = {}, c = {}; a[50] = 0; b[51] = 0; c[52] = 0;
  context.owned[first] = a; context.owned[wrong] = b; context.owned[later] = c;
  struct MatchMachine storage;
  MatchMachine machine = &storage;
  machine.open(); machine.relation = contextual_equal;
  machine.relation_context = &context;
  machine.begin(plan.program.view(), subject); machine.run();
  assert(machine.status == <ok>);
  assert(context.calls >= 2 && context.rejected >= 1);
  MachineSlot *between = &machine.slots[plan.layout.index(<*between>)];
  List captured = between.kind == MACHINE_SLOT_SPAN
                ? machine.materialize_span(between.span) : between.value.list();
  assert(captured.len() == 1 && captured.car() == wrong);
  machine.finish();
  assert(machine.clean());
  // Same machine reused: a wrong free binding cannot become a successful match.
  List miss = %(block
    (declare (int) (bindings (bind (binding 30 "outer") ())))
    $first $wrong);
  machine.begin(plan.program.view(), miss); machine.run();
  assert(machine.status == <fail>);
  machine.finish(); assert(machine.clean());
  machine.dispose(); plan.free();
  List span_pattern = %(block
    (declare (int) (bindings (bind (binding ?local ?) ())))
    *same divider *between *same);
  List span_subject = %(block
    (declare (int) (bindings (bind (binding 30 "outer") ())))
    $first divider $wrong $later);
  plan = MatchPlan.prepare(span_pattern);
  context.local_slot = plan.layout.index(<?local>);
  context.same_slot = plan.layout.index(<*same>);
  context.calls = 0; context.rejected = 0;
  machine.open(); machine.relation = contextual_equal;
  machine.relation_context = &context;
  machine.begin(plan.program.view(), span_subject); machine.run();
  assert(machine.status == <ok>);
  assert(context.calls >= 2 && context.rejected >= 1);
  between = &machine.slots[plan.layout.index(<*between>)];
  captured = between.kind == MACHINE_SLOT_SPAN
           ? machine.materialize_span(between.span) : between.value.list();
  assert(captured.len() == 1 && captured.car() == wrong);
  machine.finish(); assert(machine.clean());
  machine.dispose(); plan.free();
  List prefix_pattern = span_pattern.append(%(end));
  List prefix_subject = span_subject.append(%(end));
  plan = MatchPlan.prepare(prefix_pattern);
  context.local_slot = plan.layout.index(<?local>);
  context.same_slot = plan.layout.index(<*same>);
  context.calls = 0; context.rejected = 0;
  machine.open(); machine.relation = contextual_equal;
  machine.relation_context = &context;
  machine.begin(plan.program.view(), prefix_subject); machine.run();
  assert(machine.status == <ok>);
  assert(context.calls >= 2 && context.rejected >= 1);
  between = &machine.slots[plan.layout.index(<*between>)];
  captured = between.kind == MACHINE_SLOT_SPAN
           ? machine.materialize_span(between.span) : between.value.list();
  assert(captured.len() == 1 && captured.car() == wrong);
  machine.finish(); assert(machine.clean());
  machine.dispose(); plan.free();
  puts("relation: actual Match retries contextual alpha equality with live local slot and shadow mismatch PASS");
}

typedef struct DeferredContext {
  int local_slot, first_slot, second_slot, checks, rejected;
  Map owned;
} DeferredContext;

static int deferred_equal(void *raw_machine, int slot, Var left, Var right,
                          void *raw_context) {
  MatchMachine machine = raw_machine;
  DeferredContext *context = raw_context;
  if (slot != context.local_slot) return left == right;
  if (left != right) return 0;
  context.checks++;
  Var first = machine.slots[context.first_slot].value;
  Var second = machine.slots[context.second_slot].value;
  Map boundary = {}; boundary[right] = 0;
  int accepted = alpha_equal(first, owned_for(first, context.owned), boundary,
                             second, owned_for(second, context.owned), boundary);
  if (!accepted) context.rejected++;
  return accepted;
}

static void deferred_obligations(void) {
  List first = %(expr () (ident (binding 70 "future")));
  List wrong = %(expr () (ident (binding 71 "future")));
  List later = %(expr () (ident (binding 70 "same_binding")));
  List declaration = %(declare (int) (bindings (bind (binding 70 "future") ())));
  // Synthetic identity-bearing data tests control flow, not legal block placement.
  // !and creates an existing equality checkpoint once the later ID is captured.
  List pattern = %(seq ?first *between ?second
    (declare (int) (bindings (bind (binding (!and ?local ?local) ?) ())))
    *tail);
  List subject = %(seq $first $wrong $declaration $later $declaration);
  MatchPlan plan = MatchPlan.prepare(pattern);
  DeferredContext context;
  context.local_slot = plan.layout.index(<?local>);
  context.first_slot = plan.layout.index(<?first>);
  context.second_slot = plan.layout.index(<?second>);
  context.checks = 0; context.rejected = 0; context.owned = {};
  struct MatchMachine storage;
  MatchMachine machine = &storage;
  machine.open(); machine.relation = deferred_equal;
  machine.relation_context = &context;
  machine.begin(plan.program.view(), subject); machine.run();
  assert(machine.status == <ok>);
  assert(context.checks == 2 && context.rejected == 1);
  assert(machine.slots[context.second_slot].value == later);
  MachineSlot *between = &machine.slots[plan.layout.index(<*between>)];
  List captured = between.kind == MACHINE_SLOT_SPAN
    ? machine.materialize_span(between.span) : between.value.list();
  assert(captured.len() == 2 && captured.car() == wrong);
  machine.finish(); assert(machine.clean());
  machine.dispose(); plan.free();
  puts("deferred: later local equality checkpoint rejects prior captures and retries within Match PASS");
}

int main(void) {
  core_checks(); contextual_sequence_retry(); deferred_obligations();
  return 0;
}
