/*  test-machine.x -- shared wordcode and decoder unit tests */

#include "test-support.x"

/* Freeze `value == constant` with an explicit comparison mode:
   EQ_VALUE_CONST, RET_SUCCESS, RET_FAILURE. */
static MachineProgram _freeze_eq(Var constant, int mode) {
  MachineBuilder b = MachineBuilder.new();
  int index = b.constant(constant);
  int miss = b.emit(MW_EQ_VALUE_CONST, index, 0, 0, mode, -1);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  b.set_target(miss, b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0));
  b.root = 0;
  MachineProgram program = b.freeze();
  b.free();
  return program;
}

/* Freeze the standard binder triple for one slot: first use binds the
   current value, a repeated use compares against the bound value. */
static MachineProgram _freeze_binder(Symbol binder) {
  MachineBuilder b = MachineBuilder.new();
  int slot = b.binder(binder);
  int valid = b.emit(MW_SLOT_VALID, slot, 0, 0, 0, -1);
  b.emit(MW_SLOT_SET_VALUE, slot, 0, 0, 0, 0);
  int bound = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  int compare = b.length;
  int miss = b.emit(MW_SLOT_EQ_VALUE, slot, 0, 0, 0, -1);
  int success = b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  int failure = b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  b.set_target(valid, compare);
  b.set_target(bound, success);
  b.set_target(miss, failure);
  b.root = 0;
  MachineProgram program = b.freeze();
  b.free();
  return program;
}

static Symbol _run(MatchMachine m, MachineProgram program, Var input) {
  MatchMachine.begin(m, program.view(), input);
  MatchMachine.run(m);
  return m.status;
}

static void machine_program_is_exact_sized_and_immutable(void) {
  MachineProgram program = _freeze_eq(Var.new(<symbol>, <hello>),
                                      MACHINE_COMPARE_BITS);
  if (!EXPECT_NOT_NULL(program)) return;
  EXPECT_INT_EQ(program.length, 3);
  EXPECT_INT_EQ(program.const_count, 1);
  EXPECT_INT_EQ(program.binder_count, 0);

  size_t expected = sizeof(struct MachineProgram);
  expected = (expected + 7) / 8 * 8;
  size_t code = expected;
  expected += sizeof(MachineWord) * 3;
  expected = (expected + 7) / 8 * 8;
  size_t consts = expected;
  expected += sizeof(Var);
  expected = (expected + 7) / 8 * 8;
  MachineView view = program.view();
  EXPECT_INT_EQ((int) program.bytes(), (int) expected);
  EXPECT_INT_EQ((int) ((char *) view.code - (char *) program), (int) code);
  EXPECT_INT_EQ((int) ((char *) view.consts - (char *) program),
                (int) consts);

  struct MatchMachine storage;
  MatchMachine m = &storage;
  MatchMachine.open(m);
  EXPECT_TRUE(_run(m, program, Var.new(<symbol>, <hello>)) == <ok>);
  MatchMachine.finish(m);
  EXPECT_TRUE(_run(m, program, Var.new(<symbol>, <other>)) == <fail>);
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));
  MatchMachine.dispose(m);
  MachineProgram.free(program);
}

static void machine_builder_exhaustion_is_categorized(void) {
  MachineBuilder b = MachineBuilder.new();
  int site = 0;
  for (int i = 0; i < MACHINE_CODE_MAX + 8 && site >= 0; i++)
    site = b.emit(MW_JUMP, 0, 0, 0, 0, 0);
  EXPECT_INT_EQ(site, -1);
  EXPECT_INT_EQ(b.status, MACHINE_INELIGIBLE);
  EXPECT_STR_EQ(String.new(b.reason), "code-capacity");
  EXPECT_NULL(b.freeze());
  b.free();

  b = MachineBuilder.new();
  int index = 0;
  for (int i = 0; i < MACHINE_CONST_MAX + 8 && index >= 0; i++)
    index = b.constant(Var.new(<i32>, i));
  EXPECT_INT_EQ(index, -1);
  EXPECT_STR_EQ(String.new(b.reason), "constant-capacity");
  b.free();

  b = MachineBuilder.new();
  int slot = 0;
  for (int i = 0; i < MACHINE_BINDER_MAX + 8 && slot >= 0; i++)
    slot = b.binder(Symbol.new(String.printf("?b%d", i)));
  EXPECT_INT_EQ(slot, -1);
  EXPECT_STR_EQ(String.new(b.reason), "binder-capacity");
  b.free();
}

static void machine_public_preconditions_transfer(void) {
  int caught = 0;
  MachineBuilder b = MachineBuilder.new();
  int site = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  try b.set_target(site, -1);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(b.code[site].target, -1);
  try b.patch(&site, 1, -1);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(b.code[site].target, -1);
  b.free();

  struct LispMachine lisp_storage;
  LispMachine lisp = &lisp_storage;
  LispMachine.open(lisp);
  MachineView empty = {0};
  try lisp.begin(empty, NULL, NULL, -1);
  catch %(bad-arity *): caught++;
  EXPECT_TRUE(lisp.clean());
  try lisp.begin(empty, NULL, NULL, MACHINE_LOCAL_MAX + 1);
  catch %(bad-arity *): caught++;
  EXPECT_TRUE(lisp.clean());

  struct MatchMachine storage;
  MatchMachine m = &storage;
  MatchMachine.open(m);
  MachineProgram program = _freeze_eq(1, MACHINE_COMPARE_BITS);
  if (EXPECT_NOT_NULL(program)) {
    m.begin(program.view(), 1);
    try m.finish();
    catch %(bad-state *): caught++;
    EXPECT_TRUE(m.running);
    m.run();
    m.finish();
    EXPECT_TRUE(m.clean());
    MachineProgram.free(program);
  }
  MatchMachine.dispose(m);
  EXPECT_INT_EQ(caught, 5);
}

/* The wordcode equivalent of pattern (?x ?x): a root segment calling
   the binder triple for each element.  Proves nested calls, success
   and failure returns, and root-failure journal rollback. */
static void machine_nested_calls_return_and_rollback(void) {
  MachineBuilder b = MachineBuilder.new();
  int slot = b.binder(<?x>);
  int child = b.length;
  int valid = b.emit(MW_SLOT_VALID, slot, 0, 0, 0, -1);
  b.emit(MW_SLOT_SET_VALUE, slot, 0, 0, 0, 0);
  int bound = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  int compare = b.length;
  int miss = b.emit(MW_SLOT_EQ_VALUE, slot, 0, 0, 0, -1);
  int child_ok = b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  int child_fail = b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  b.set_target(valid, compare);
  b.set_target(bound, child_ok);
  b.set_target(miss, child_fail);

  int failures[8], failure_count = 0, root = b.length;
  failures[failure_count++] = b.emit(MW_INPUT_LIST, 0, 0, 0, 0, -1);
  for (int i = 0; i < 2; i++) {
    failures[failure_count++] = b.emit(MW_NONNIL, 0, 0, 0, 0, -1);
    b.emit(MW_CALL, child, MACHINE_CALL_HEAD, 0, 0, 0);
    failures[failure_count++] = b.emit(MW_BR_FAIL, 0, 0, 0, 0, -1);
    b.emit(MW_ADVANCE, 0, 0, 0, 0, 0);
  }
  failures[failure_count++] = b.emit(MW_NIL, 0, 0, 0, 0, -1);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  b.patch(failures, failure_count, b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0));
  b.root = root;
  MachineProgram program = b.freeze();
  b.free();
  if (!EXPECT_NOT_NULL(program)) return;

  struct MatchMachine storage;
  MatchMachine m = &storage;
  MatchMachine.open(m);
  MachineStats stats;
  memset(&stats, 0, sizeof(stats));
  m.stats = &stats;

  MachineSlot *slots = m.slots;
  EXPECT_TRUE(_run(m, program, %(ok ok)) == <ok>);
  EXPECT_INT_EQ(slots[0].kind, MACHINE_SLOT_VALUE);
  EXPECT_VAR_EQ(slots[0].value, Var.new(<symbol>, <ok>));
  EXPECT_INT_EQ(stats.max_frames, 2);
  EXPECT_TRUE(stats.calls == 3 && stats.returns == 3);
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));

  EXPECT_TRUE(_run(m, program, %(ok other)) == <fail>);
  EXPECT_INT_EQ(slots[0].kind, MACHINE_SLOT_INVALID);
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));
  MatchMachine.dispose(m);
  MachineProgram.free(program);
}

static void machine_error_unwinds_to_clean_state(void) {
  MachineBuilder b = MachineBuilder.new();
  int miss = b.emit(MW_INPUT_LIST, 0, 0, 0, 0, -1);
  b.emit(MW_ADVANCE, 0, 0, 0, 0, 0);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  b.set_target(miss, b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0));
  b.root = 0;
  MachineProgram program = b.freeze();
  b.free();
  if (!EXPECT_NOT_NULL(program)) return;

  struct MatchMachine storage;
  MatchMachine m = &storage;
  MatchMachine.open(m);
  EXPECT_TRUE(_run(m, program, Var.new(<list>, NULL)) == <error>);
  EXPECT_VAR_EQ(m.error, Var.new(<symbol>, <advance>));
  EXPECT_FALSE(m.running);
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));
  MatchMachine.dispose(m);
  MachineProgram.free(program);
}

/* A caller distinguishes two machine faults by comparing the code, so a
   CALL with an empty head must not report the ADVANCE code.  Compact
   Symbols hold ten alphabet characters and silently drop the rest, so
   every code is short enough to survive encoding whole. */
static void machine_error_codes_are_distinct(void) {
  MachineBuilder b = MachineBuilder.new();
  int miss = b.emit(MW_INPUT_LIST, 0, 0, 0, 0, -1);
  b.emit(MW_CALL, 0, MACHINE_CALL_HEAD, 0, 0, 0);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  b.set_target(miss, b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0));
  b.root = 0;
  MachineProgram program = b.freeze();
  b.free();
  if (!EXPECT_NOT_NULL(program)) return;

  struct MatchMachine storage;
  MatchMachine m = &storage;
  MatchMachine.open(m);
  EXPECT_TRUE(_run(m, program, Var.new(<list>, NULL)) == <error>);
  EXPECT_VAR_EQ(m.error, Var.new(<symbol>, <call-head>));
  EXPECT_FALSE(m.error.equal(Var.new(<symbol>, <advance>)));
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));
  MatchMachine.dispose(m);
  MachineProgram.free(program);

  Symbol codes[] = { <advance>, <bad-local>, <bad-span>, <bad-word>,
                     <call-head>, <call-stack>, <frame-max>,
                     <local-max>, <no-operand>, <no-result>, <not-idle>,
                     <quasi-tail>, <slot-state>, <undo-max>, <value-max> };
  int count = (int) (sizeof(codes) / sizeof(codes[0])), collisions = 0;
  for (int i = 0; i < count; i++)
    for (int j = i + 1; j < count; j++)
      if (codes[i] == codes[j]) collisions++;
  EXPECT_INT_EQ(collisions, 0);
}

static void machine_frame_capacity_is_checked(void) {
  MachineBuilder b = MachineBuilder.new();
  b.emit(MW_CALL, 0, MACHINE_CALL_CURRENT, 0, 0, 0);
  int branch = b.emit(MW_BR_FAIL, 0, 0, 0, 0, -1);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  b.set_target(branch, b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0));
  b.root = 0;
  MachineProgram program = b.freeze();
  b.free();
  if (!EXPECT_NOT_NULL(program)) return;

  struct MatchMachine storage;
  MatchMachine m = &storage;
  MatchMachine.open(m);
  EXPECT_TRUE(_run(m, program, Var.new(<symbol>, <loop>)) == <error>);
  EXPECT_VAR_EQ(m.error, Var.new(<symbol>, <frame-max>));
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));
  MatchMachine.dispose(m);
  MachineProgram.free(program);
}

/* A legal program journals at most two transitions per binder, so the
   undo fence is unreachable by construction; assert that invariant and
   prove the slot-state owner rejects an illegal repeated write. */
static void machine_slot_state_errors_are_checked(void) {
  EXPECT_TRUE(MACHINE_UNDO_MAX >= 4 * MACHINE_BINDER_MAX);
  MachineBuilder b = MachineBuilder.new();
  int slot = b.binder(<?x>);
  int loop = b.length;
  b.emit(MW_SLOT_SET_VALUE, slot, 0, 0, 0, 0);
  b.emit(MW_JUMP, 0, 0, 0, 0, loop);
  b.root = 0;
  MachineProgram program = b.freeze();
  b.free();
  if (!EXPECT_NOT_NULL(program)) return;

  struct MatchMachine storage;
  MatchMachine m = &storage;
  MatchMachine.open(m);
  EXPECT_TRUE(_run(m, program, Var.new(<symbol>, <value>)) == <error>);
  EXPECT_VAR_EQ(m.error, Var.new(<symbol>, <slot-state>));
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));
  MatchMachine.dispose(m);
  MachineProgram.free(program);
}

static void machine_instances_interleave_independently(void) {
  MachineProgram eq = _freeze_eq(Var.new(<symbol>, <alpha>),
                                 MACHINE_COMPARE_BITS);
  MachineProgram binder = _freeze_binder(<?x>);
  if (!EXPECT_NOT_NULL(eq) || !EXPECT_NOT_NULL(binder)) return;

  struct MatchMachine storage_a, storage_b;
  MatchMachine a = &storage_a, b = &storage_b;
  MatchMachine.open(a);
  MatchMachine.open(b);
  MatchMachine.begin(a, eq.view(), Var.new(<symbol>, <alpha>));
  MatchMachine.begin(b, binder.view(), Var.new(<symbol>, <captured>));
  int live_a = 1, live_b = 1;
  while (live_a || live_b) {
    if (live_a) live_a = MatchMachine.step(a);
    if (live_b) live_b = MatchMachine.step(b);
  }
  EXPECT_TRUE(a.status == <ok>);
  EXPECT_TRUE(b.status == <ok>);
  MachineSlot *b_slots = b.slots;
  EXPECT_VAR_EQ(b_slots[0].value, Var.new(<symbol>, <captured>));
  MatchMachine.finish(a);
  MatchMachine.finish(b);
  EXPECT_TRUE(MatchMachine.clean(a) && MatchMachine.clean(b));
  MatchMachine.dispose(a);
  MatchMachine.dispose(b);
  MachineProgram.free(eq);
  MachineProgram.free(binder);
}

/* A hand-lowered anchored scan: losing runs construct no span and no
   cells; the winning run defers one span and materializes exactly one
   public copy.  A complete-suffix span shares the input directly. */
static void machine_scan_binds_lazy_spans_only_on_success(void) {
  MachineBuilder b = MachineBuilder.new();
  int slot = b.binder(<"*pre">);
  int anchor = b.constant(Var.new(<symbol>, <mark>));
  int failures[2];
  failures[0] = b.emit(MW_INPUT_LIST, 0, 0, 0, 0, -1);
  b.emit(MW_MOVE, 1, 0, 0, 0, 0);
  b.emit(MW_MOVE, 2, 1, 0, 0, 0);
  failures[1] = b.emit(MW_SCAN, 1, 2, anchor, MACHINE_COMPARE_BITS, -1);
  b.emit(MW_SLOT_SET_SPAN, slot, 0, 1, 0, 0);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  b.patch(failures, 2, b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0));
  b.root = 0;
  MachineProgram program = b.freeze();
  b.free();
  if (!EXPECT_NOT_NULL(program)) return;

  struct MatchMachine storage;
  MatchMachine m = &storage;
  MatchMachine.open(m);
  MachineStats stats;
  memset(&stats, 0, sizeof(stats));
  m.stats = &stats;

  EXPECT_TRUE(_run(m, program, %(a b c)) == <fail>);
  EXPECT_INT_EQ((int) stats.span_descriptors, 0);
  EXPECT_INT_EQ((int) stats.materialization_requests, 0);
  EXPECT_INT_EQ((int) stats.cons_requests, 0);
  EXPECT_INT_EQ((int) stats.scan_cells, 3);
  MatchMachine.finish(m);

  EXPECT_TRUE(_run(m, program, %(a b mark c)) == <ok>);
  EXPECT_INT_EQ((int) stats.span_descriptors, 1);
  MachineSlot *slots = m.slots;
  EXPECT_INT_EQ(slots[0].kind, MACHINE_SLOT_SPAN);
  EXPECT_INT_EQ(slots[0].span.length, 2);
  List prefix = MatchMachine.materialize_span(m, slots[0].span);
  EXPECT_TRUE(prefix == %(a b));
  EXPECT_INT_EQ((int) stats.materialization_completions, 1);
  EXPECT_INT_EQ((int) stats.materialized_cells, 2);
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));

  List whole = %(x y z);
  MachineSpan suffix = { whole, NULL, 3 };
  EXPECT_TRUE(MatchMachine.materialize_span(m, suffix) == whole);
  EXPECT_INT_EQ((int) stats.direct_shares, 1);
  MatchMachine.dispose(m);
  MachineProgram.free(program);
}

static void machine_compare_modes_respect_boxed_values(void) {
  Var boxed = Var.box_long(3);
  MachineProgram equal = _freeze_eq(boxed, MACHINE_COMPARE_EQUAL);
  MachineProgram bits = _freeze_eq(boxed, MACHINE_COMPARE_BITS);
  if (!EXPECT_NOT_NULL(equal) || !EXPECT_NOT_NULL(bits)) return;

  struct MatchMachine storage;
  MatchMachine m = &storage;
  MatchMachine.open(m);
  Var twin = Var.box_long(3);
  EXPECT_TRUE(twin.u64 != boxed.u64);
  EXPECT_TRUE(_run(m, equal, twin) == <ok>);
  MatchMachine.finish(m);
  EXPECT_TRUE(_run(m, bits, twin) == <fail>);
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));
  MatchMachine.dispose(m);
  MachineProgram.free(equal);
  MachineProgram.free(bits);
}

static void machine_storage_reuse_and_dirty_begin(void) {
  MachineProgram eq = _freeze_eq(Var.new(<symbol>, <alpha>),
                                 MACHINE_COMPARE_BITS);
  MachineProgram binder = _freeze_binder(<?y>);
  if (!EXPECT_NOT_NULL(eq) || !EXPECT_NOT_NULL(binder)) return;

  struct MatchMachine storage;
  MatchMachine m = &storage;
  MatchMachine.open(m);
  EXPECT_TRUE(_run(m, eq, Var.new(<symbol>, <alpha>)) == <ok>);
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));
  MachineSlot *slots = m.slots;
  EXPECT_TRUE(_run(m, binder, Var.new(<i32>, 7)) == <ok>);
  EXPECT_INT_EQ(slots[0].kind, MACHINE_SLOT_VALUE);
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));

  MatchMachine.begin(m, eq.view(), Var.new(<symbol>, <alpha>));
  MatchMachine.begin(m, eq.view(), Var.new(<symbol>, <alpha>));
  EXPECT_TRUE(m.status == <error>);
  EXPECT_VAR_EQ(m.error, Var.new(<symbol>, <not-idle>));
  MatchMachine.finish(m);
  EXPECT_TRUE(MatchMachine.clean(m));
  MatchMachine.dispose(m);
  MachineProgram.free(eq);
  MachineProgram.free(binder);
}

$(import "test-macros.xmacro")

void machine_suite(void) {
  $test.run(machine_program_is_exact_sized_and_immutable);
  $test.run(machine_builder_exhaustion_is_categorized);
  $test.run(machine_public_preconditions_transfer);
  $test.run(machine_nested_calls_return_and_rollback);
  $test.run(machine_error_unwinds_to_clean_state);
  $test.run(machine_error_codes_are_distinct);
  $test.run(machine_frame_capacity_is_checked);
  $test.run(machine_slot_state_errors_are_checked);
  $test.run(machine_instances_interleave_independently);
  $test.run(machine_scan_binds_lazy_spans_only_on_success);
  $test.run(machine_compare_modes_respect_boxed_values);
  $test.run(machine_storage_reuse_and_dirty_begin);
}
