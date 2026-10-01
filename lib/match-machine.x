/*  match-machine.x -- `Match` wordcode execution

    Copyright (c) 2026 Gary William Flake.

    Runs immutable `Match` programs prepared by MatchPlan. Each invocation owns
    its frames, registers, capture slots, undo journal, and optional span
    materialization scratch. Instructions call `Match`'s canonical binder
    predicates for pattern classification.
*/

#pragma once

#include "machine.x"

#pragma private

#include <assert.h>
#include <string.h>
#include "scope.x"
#include "array.x"
#include "exception.x"
#include "match.x"

// operands

static List *MatchMachine._cursor(MatchMachine m, int reg) =>
  &m.regs[m.fp].cursors[reg];

static int *MatchMachine._distance(MatchMachine m, int reg) =>
  &m.regs[m.fp].distances[reg];

static int *MatchMachine._int_reg(MatchMachine m, int reg) =>
  &m.regs[m.fp].ints[reg];

static MachineMark *MatchMachine._mark(MatchMachine m) => &m.regs[m.fp].mark;

static Var MatchMachine._const(MatchMachine m, int index) =>
  m.program.consts[index];

static void MatchMachine._clear_registers(MatchMachine m, int depth) {
  memset(&m.regs[depth], 0, sizeof(MachineRegs));
}

// execution

/* Execute Match words until success, failure, or a stored machine error. */
void MatchMachine.run(MatchMachine m) {
  while (m.step()) {}
}

/* Execute one Match word and report whether another word remains. Fetch
   advances pc before dispatch, so calls save the following word and branches
   replace it. Machine invariant failures roll back all captures and store an
   error; predicates that raise can instead transfer out while the machine is
   marked running. */
int MatchMachine.step(MatchMachine m) {
  if (!m.running) return 0;
  m._execute(&m.program.code[m.pc++]);
  return m.running;
}

static void MatchMachine._execute(MatchMachine m, const MachineWord *w) {
  switch (w.op) {
    case MW_EQ_VALUE_CONST:
      if (!_equal(w.d, m.value, m._const(w.a))) m.pc = w.target;
      break;
    case MW_EQ_VALUE_BITS:
      if (m.value.u64 != m._const(w.a).u64) m.pc = w.target;
      break;
    case MW_INPUT_LIST: if (!m._enter(w.a, m.value)) m.pc = w.target; break;
    case MW_NONNIL: if (!*m._cursor(w.a)) m.pc = w.target; break;
    case MW_NIL: if (*m._cursor(w.a)) m.pc = w.target; break;
    case MW_CALL: m._call(w); break;
    case MW_BR_FAIL: if (m.status != <ok>) m.pc = w.target; break;
    case MW_JUMP: m.pc = w.target; break;
    case MW_ADVANCE: if (!m._advance(w.a)) m._error(<advance>); break;
    case MW_ADVANCE_OPTIONAL:
      if (!m._advance(w.a)) *m._int_reg(w.b) = 0;
      break;
    case MW_MOVE: m._move(w); break;
    case MW_OFFSET: m._offset(w); break;
    case MW_DESCEND: m._descend(w); break;
    case MW_SCAN: m._scan(w); break;
    case MW_SET_ACTIVE: *m._int_reg(w.a) = w.b; break;
    case MW_REQUIRE_ACTIVE: if (!*m._int_reg(w.a)) m.pc = w.target; break;
    case MW_MARK: m._mark().undo_count = m.undo_count; break;
    case MW_ROLLBACK: m._restore(w); break;
    case MW_SLOT_VALID:
      if (m.slots[w.a].kind != MACHINE_SLOT_INVALID) m.pc = w.target;
      break;
    case MW_SLOT_IS_SPAN:
      if (m.slots[w.a].kind == MACHINE_SLOT_SPAN) m.pc = w.target;
      break;
    case MW_SLOT_SET_VALUE: m._set_value(w.a, m.value, w.b); break;
    case MW_SLOT_SET_SPAN: m._set_span(w); break;
    case MW_SLOT_EQ_VALUE:
      if (!m._value_equal(w.a, m.value)) m.pc = w.target;
      break;
    case MW_SLOT_EQ_PREFIX: m._eq_prefix(w); break;
    case MW_SLOT_EQ_FINAL_IDENTITY:
      if (!m._sequence_equal(w.a, *m._cursor(w.b), 0, 1)) m.pc = w.target;
      break;
    case MW_CURSOR_VALUE: m._cursor_value(w); break;
    case MW_EQ_HEAD_CONST: m._eq_head(w); break;
    case MW_BIND_HEAD: m._bind_head(w); break;
    case MW_SKIP_HEAD: if (!m._advance(w.b)) m.pc = w.target; break;
    case MW_RET_SUCCESS: m._return(<ok>); break;
    case MW_RET_FAILURE: m._return(<fail>); break;
    case MW_TAG: m._tag(w); break;
    case MW_MATCH_KIND:
      if (!_is_kind(m.value, w.b)) m.pc = w.target;
      break;
    default: m._error(<bad-word>);
  }
}

// value tests

/* Compares by raw Var bits or by language equality, as `mode` selects. */
static int _equal(int mode, Var left, Var right) =>
  mode == MACHINE_COMPARE_BITS ? left.u64 == right.u64 : left == right;

static void MatchMachine._tag(MatchMachine m, const MachineWord *w) {
  Symbol tag = m._const(w.a);
  if (m.value is not tag) m.pc = w.target;
}

static int _is_kind(Var value, int kind) {
  switch (kind) {
    case MACHINE_KIND_ATOM_BINDER: return value.is_atom_binder();
    case MACHINE_KIND_LIST_BINDER: return value.is_list_binder();
    case MACHINE_KIND_BINDER:      return value.is_binder();
    case MACHINE_KIND_MATCH_OP:    return value.is_match_op();
  }
  return 0;
}

/* list cursors

   A cursor register holds the rest of a List, and its distance counts the
   cells passed since the machine entered that List. */

/* Starts cursor `reg` on the List the optional view shows for `input`, or
   returns 0 when that is not a List. */
static int MatchMachine._enter(MatchMachine m, int reg, Var input) {
  Var seen = m.view ? m.view(input) : input;
  if (seen is not <list>) return 0;
  *m._cursor(reg) = seen;
  *m._distance(reg) = 0;
  return 1;
}

/* Moves cursor `reg` one cell, or returns 0 when it is empty. */
static int MatchMachine._advance(MatchMachine m, int reg) {
  List at = *m._cursor(reg);
  if (!at) return 0;
  m._skip(reg, at);
  return 1;
}

static void MatchMachine._move(MatchMachine m, const MachineWord *w) {
  *m._cursor(w.a) = *m._cursor(w.b);
  *m._distance(w.a) = *m._distance(w.b);
}

/* Advances cursor `a` by up to `b` cells. */
static void MatchMachine._offset(MatchMachine m, const MachineWord *w) {
  for (int n = 0; n < w.b; n++) if (!m._advance(w.a)) return;
}

/* Enters the List at the head of cursor `b` through `c`, the bank's next
   register. No call frame is pushed. */
static void MatchMachine._descend(MatchMachine m, const MachineWord *w) {
  List at = *m._cursor(w.b);
  if (!at || !m._enter(w.c, at.car())) m.pc = w.target;
}

/* The split and probe cursors advance in lockstep until the probe finds
   the anchor or runs off the end of the input. Both cursors and both
   distances remain visible afterward. */
static void MatchMachine._scan(MatchMachine m, const MachineWord *w) {
  List split = *m._cursor(w.a), probe = *m._cursor(w.b);
  int split_distance = *m._distance(w.a), probe_distance = *m._distance(w.b);
  Var anchor = m._const(w.c);
  while (probe) {
    if (m.stats) m.stats.scan_cells++;
    if (_equal(w.d, probe.car(), anchor)) break;
    split = split.cdr();
    probe = probe.cdr();
    split_distance++;
    probe_distance++;
  }
  *m._cursor(w.a) = split;
  *m._cursor(w.b) = probe;
  *m._distance(w.a) = split_distance;
  *m._distance(w.b) = probe_distance;
  if (!probe) m.pc = w.target;
}

/* Makes cursor `a` the current value; a nonzero `b` counts the shared List
   as a materialization avoided. */
static void MatchMachine._cursor_value(MatchMachine m, const MachineWord *w) {
  m.value = *m._cursor(w.a);
  if (w.b) m._count_share();
}

/* Moves cursor `reg` past the head of `at`, the List it holds. */
static void MatchMachine._skip(MatchMachine m, int reg, List at) {
  *m._cursor(reg) = at.cdr();
  (*m._distance(reg))++;
}

/* calls

   A call runs its subprogram in a new frame with a cleared register bank,
   and the return restores the caller's pc, undo position, and value. */

/* Calls the subprogram at `a` on the value `b` selects: the current value,
   or cursor `c` or its head, read from the caller's bank. */
static void MatchMachine._call(MatchMachine m, const MachineWord *w) {
  Var argument = m.value;
  if (w.b == MACHINE_CALL_HEAD) {
    List at = *m._cursor(w.c);
    if (!at) {
      m._error(<call-head>);
      return;
    }
    argument = at.car();
  }
  else if (w.b == MACHINE_CALL_CURSOR) argument = *m._cursor(w.c);
  m._push_frame(argument, w.a);
}

/* Saves the caller's state in a new frame and continues at `entry` on
   `argument`. */
static void MatchMachine._push_frame(MatchMachine m, Var argument, int entry) {
  if (m.fp + 1 >= MACHINE_FRAME_MAX) {
    m._error(<frame-max>);
    return;
  }
  m.frames[m.fp++] = (MatchFrame) {m.pc, m.current_entry_undo, m.value};
  m._clear_registers(m.fp);
  m.current_entry_undo = m.undo_count;
  m._count_call();
  m.value = argument;
  m.pc = entry;
}

/* Returns from the current subprogram with <ok> or <fail>. A failure rolls
   back to the subprogram's entry position, and the root's return stops the
   machine. */
static void MatchMachine._return(MatchMachine m, Symbol status) {
  if (status == <fail>) m._rollback(m.current_entry_undo);
  m.status = status;
  if (m.stats) m.stats.returns++;
  m._clear_registers(m.fp);
  if (m.fp) m._pop_frame();
  else m.running = 0;
}

static void MatchMachine._pop_frame(MatchMachine m) {
  assert(m.fp > 0);
  MatchFrame *frame = &m.frames[--m.fp];
  m.pc = frame.return_pc;
  m.current_entry_undo = frame.caller_entry_undo;
  m.value = frame.caller_value;
}

/* captures

   Journal every slot replacement before mutation. A failed subprogram rolls
   back to its entry position; an enclosing failure can still undo successful
   inner captures because their entries remain in the shared journal. */

/* Captures `value` in slot `index`. The slot must be unset or, with
   `replace_span`, hold the span whose materialized List `value` memoizes. */
static void MatchMachine._set_value(
  MatchMachine m, int index, Var value, int replace_span) {
  MachineSlot capture = {.kind = MACHINE_SLOT_VALUE, .value = value};
  MachineSlotKind expected =
    replace_span ? MACHINE_SLOT_SPAN : MACHINE_SLOT_INVALID;
  if (m.slots[index].kind != expected) m._error(<slot-state>);
  else m._journal(index, capture);
}

/* Captures the cells from cursor `b` to cursor `c` in the unset slot `a` as
   a borrowed span. */
static void MatchMachine._set_span(MatchMachine m, const MachineWord *w) {
  int length = *m._distance(w.c) - *m._distance(w.b);
  MachineSlot capture = {
    .kind = MACHINE_SLOT_SPAN,
    .span = (MachineSpan) {*m._cursor(w.b), *m._cursor(w.c), length}};
  if (m.stats) m.stats.span_descriptors++;
  if (m.slots[w.a].kind != MACHINE_SLOT_INVALID) m._error(<slot-state>);
  else m._journal(w.a, capture);
}

static void MatchMachine._journal(
  MatchMachine m, int index, MachineSlot capture) {
  if (m.undo_count >= MACHINE_UNDO_MAX) {
    m._error(<undo-max>);
    return;
  }
  MachineUndo *entry = &m.undo[m.undo_count++];
  entry.slot = index;
  entry.prior = m.slots[index];
  m.slots[index] = capture;
}

static void MatchMachine._rollback(MatchMachine m, int mark) {
  while (m.undo_count > mark) {
    MachineUndo undo = m.undo[--m.undo_count];
    m.slots[undo.slot] = undo.prior;
  }
}

/* Rolls back to the frame's mark; `b` tells a measured retry from an
   ordinary restore. */
static void MatchMachine._restore(MatchMachine m, const MachineWord *w) {
  m._rollback(m._mark().undo_count);
  if (m.stats && w.b == MACHINE_ROLLBACK_RETRY) m.stats.retries++;
}

static int MatchMachine._value_equal(MatchMachine m, int index, Var value) {
  MachineSlot *slot = &m.slots[index];
  if (slot.kind != MACHINE_SLOT_VALUE) return 0;
  if (m.relation)
    return m.relation(m, index, slot.value, value, m.relation_context);
  return slot.value == value;
}

/* Compares slot `a` with the cells from cursor `b` to cursor `c`. */
static void MatchMachine._eq_prefix(MatchMachine m, const MachineWord *w) {
  int length = *m._distance(w.c) - *m._distance(w.b);
  if (!m._sequence_equal(w.a, *m._cursor(w.b), length, 0)) m.pc = w.target;
}

/* Compares slot `index` with the first `length` cells of `input`, or with
   all of `input` when `final` is set. A comparison under a relation
   materializes both sides once; the default path keeps the allocation-free
   span comparison. Both sequence words call this one function, so the C
   compiler does not inline its relation path into the interpreter loop. */
static int MatchMachine._sequence_equal(
  MatchMachine m, int index, List input, int length, int final) {
  MachineSlot *slot = &m.slots[index];
  if (!m.relation)
    return final ? slot.final_equal(input, m.stats)
                 : slot.prefix_equal(input, length, m.stats);
  List expected = slot.kind == MACHINE_SLOT_SPAN
    ? m.materialize_span(slot.span) : slot.value.list();
  if (m.status == <error>) return 0;
  if (final) return m.relation(m, index, expected, input, m.relation_context);
  Array items = [];
  for (int n = 0; n < length; n++) {
    if (!input) return 0;
    items.push(input.car());
    input = input.cdr();
  }
  return m.relation(m, index, expected, items.list_free(), m.relation_context);
}

/* fused head words

   Each fused leaf-element word subsumes the NONNIL guard, the one-value
   child a CALL frame would execute against the cursor head, and the
   ADVANCE. Journal and comparison behavior matches the framed lowering. */

static void MatchMachine._eq_head(MatchMachine m, const MachineWord *w) {
  List at = *m._cursor(w.b);
  if (at && _equal(w.d, at.car(), m._const(w.a))) m._skip(w.b, at);
  else m.pc = w.target;
}

static void MatchMachine._bind_head(MatchMachine m, const MachineWord *w) {
  List at = *m._cursor(w.b);
  if (!at) m.pc = w.target;
  else if (m.slots[w.a].kind == MACHINE_SLOT_INVALID) {
    m._set_value(w.a, at.car(), 0);
    if (m.status != <error>) m._skip(w.b, at);
  }
  else if (m._value_equal(w.a, at.car())) m._skip(w.b, at);
  else m.pc = w.target;
}

// spans

/* Materialize a borrowed span. A complete suffix shares the existing
   immutable List directly, an empty span returns nil, and a proper prefix
   copies through growable machine scratch once. An invalid end stores
   <bad-span>; allocation and consing can raise. */
List MatchMachine.materialize_span(MatchMachine m, MachineSpan span) {
  if (m.stats) m.stats.materialization_requests++;
  if (!span.end) {
    m._count_share();
    return span.begin;
  }
  if (span.length && !m._copy_span(span)) {
    m._error(<bad-span>);
    return NULL;
  }
  List out = m._cons_scratch(span.length);
  if (m.stats) m.stats.materialization_completions++;
  return out;
}

/* Copies the span's cells into scratch, or returns 0 when its List ends
   early or at a cell other than `end`. */
static int MatchMachine._copy_span(MatchMachine m, MachineSpan span) {
  m._ensure_scratch(span.length);
  List at = span.begin;
  for (int i = 0; i < span.length; i++) {
    if (!at) return 0;
    m.scratch[i] = at.car();
    at = at.cdr();
    if (m.stats) m.stats.materialized_cells++;
  }
  return at == span.end;
}

static void MatchMachine._ensure_scratch(MatchMachine m, int length) {
  if (length <= m.scratch_capacity) return;
  int capacity = m.scratch_capacity ? m.scratch_capacity : 16;
  while (capacity < length) capacity *= 2;
  Var *grown = Scope.realloc(m.scratch, sizeof(Var) * capacity);
  m.scratch = grown;
  m.scratch_capacity = capacity;
}

static List MatchMachine._cons_scratch(MatchMachine m, int length) {
  List out = NULL;
  for (int i = length; i; i--) {
    if (m.stats) m.stats.cons_requests++;
    out = cons(m.scratch[i - 1], out);
  }
  return out;
}

// errors and statistics

/* A code reaches the caller as the `why` detail of the Machine invariant and
   is told apart by comparison. Each one stays within the ten alphabet
   characters a compact Symbol holds. */
static void MatchMachine._error(MatchMachine m, Symbol code) {
  m._rollback(0);
  m._clear_frames();
  m.current_entry_undo = 0;
  m.error = code;
  m.status = <error>;
  m.running = 0;
}

static void MatchMachine._count_call(MatchMachine m) {
  if (!m.stats) return;
  m.stats.calls++;
  if (m.fp + 1 > m.stats.max_frames) m.stats.max_frames = m.fp + 1;
}

static void MatchMachine._count_share(MatchMachine m) {
  if (!m.stats) return;
  m.stats.direct_shares++;
  m.stats.materializations_avoided++;
}

// lifecycle

/* Initialize fresh caller-owned storage without touching unused fixed
   arrays. The caller must eventually dispose any materialization scratch. */
void MatchMachine.open(MatchMachine m) {
  memset(&m.program, 0, sizeof(MachineView));
  m.pc = 0;
  m.status = <idle>;
  m.running = 0;
  m.value = void;
  m.error = void;
  m.fp = 0;
  m.current_entry_undo = 0;
  m.undo_count = 0;
  m.slot_count = 0;
  m.stats = NULL;
  m.relation = NULL;
  m.relation_context = NULL;
  m.view = NULL;
  m.scratch = NULL;
  m.scratch_capacity = 0;
}

/* Begin execution of a valid Match program in opened, completed storage and
   borrow its view and input Lists until finish. Zero undo entries prove every
   slot of the previous program was restored, so only the new program's binder
   slots are initialized. A dirty machine records <not-idle> and stops. */
void MatchMachine.begin(MatchMachine m, MachineView program, Var input) {
  if (m.running || m.undo_count || m.fp) {
    m._error(<not-idle>);
    return;
  }
  m.program = program;
  m.pc = program.root;
  m.status = <running>;
  m.running = 1;
  m.value = input;
  m.error = void;
  m.current_entry_undo = 0;
  m.slot_count = program.binder_count;
  m._clear_slots();
  m._clear_registers(0);
  m._count_call();
}

/* Return a stopped invocation to idle and clear its borrowed execution state.
   Reusable scratch and the optional stats pointer remain installed.

   Raises: `<bad-state>` when execution is still running. */
void MatchMachine.finish(MatchMachine m) {
  if (m.running) raise %(bad-state (owner "MatchMachine.finish"));
  m._clear_slots();
  m._clear_frames();
  m.slot_count = 0;
  m.undo_count = 0;
  m.current_entry_undo = 0;
  m.pc = 0;
  m.value = void;
  m.error = void;
  m.status = <idle>;
  memset(&m.program, 0, sizeof(MachineView));
  m.running = 0;
}

/* Report whether the observable invocation state is idle and cleared. Scratch
   capacity and the optional stats pointer do not affect the answer. */
int MatchMachine.clean(MatchMachine m) {
  if (m.running || m.program.code || m.fp || m.undo_count || m.slot_count)
    return 0;
  return m.status == <idle> && m.error is void;
}

/* Free reusable materialization scratch. Finish active execution first;
   this does not clear invocation state. */
void MatchMachine.dispose(MatchMachine m) {
  if (m.scratch) Scope.free(m.scratch);
  m.scratch = NULL;
  m.scratch_capacity = 0;
}

static void MatchMachine._clear_slots(MatchMachine m) {
  for (int i = 0; i < m.slot_count; i++) {
    memset(&m.slots[i], 0, sizeof(MachineSlot));
    m.slots[i].kind = MACHINE_SLOT_INVALID;
  }
}

/* Clears every active frame's register bank and returns to the root frame. */
static void MatchMachine._clear_frames(MatchMachine m) {
  for (int depth = 0; depth <= m.fp; depth++) m._clear_registers(depth);
  m.fp = 0;
}
