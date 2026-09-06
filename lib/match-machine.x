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
#include "exception.x"
#include "match.x"

static List *MatchMachine._cursor(MatchMachine m, int reg) =>
  &m.regs[m.fp].cursors[reg];

static int *MatchMachine._distance(MatchMachine m, int reg) =>
  &m.regs[m.fp].distances[reg];

static int *MatchMachine._int_reg(MatchMachine m, int reg) =>
  &m.regs[m.fp].ints[reg];

static MachineMark *MatchMachine._mark(MatchMachine m) => &m.regs[m.fp].mark;

/* Initialize fresh caller-owned storage without touching unused fixed arrays.
   The caller must eventually dispose any materialization scratch. */
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
  m.scratch = NULL;
  m.scratch_capacity = 0;
}

static void MatchMachine._rollback(MatchMachine m, int undo_mark) {
  while (m.undo_count > undo_mark) {
    MachineUndo undo = m.undo[--m.undo_count];
    m.slots[undo.slot] = undo.prior;
  }
}

static void MatchMachine._clear_registers(MatchMachine m, int depth) {
  memset(&m.regs[depth], 0, sizeof(MachineRegs));
}

static void MatchMachine._error_value(MatchMachine m, Var error) {
  m._rollback(0);
  for (int depth = 0; depth <= m.fp; depth++) m._clear_registers(depth);
  m.fp = 0;
  m.current_entry_undo = 0;
  m.error = error;
  m.status = <error>;
  m.running = 0;
}

/* A code reaches the caller as the `why` detail of the Machine invariant and
   is told apart by comparison. Each one stays within the ten alphabet
   characters a compact Symbol holds. */
static void MatchMachine._error(MatchMachine m, Symbol error) {
  m._error_value(error);
}

/* Journal every slot replacement before mutation. A failed subprogram rolls
   back to its entry position; an enclosing failure can still undo successful
   inner captures because their entries remain in the shared journal. */
static void MatchMachine._journal_slot(
  MatchMachine m, int slot, MachineSlot value) {
  if (m.undo_count >= MACHINE_UNDO_MAX) {
    m._error(<undo-max>);
    return;
  }
  m.undo[m.undo_count].slot = slot;
  m.undo[m.undo_count].prior = m.slots[slot];
  m.undo_count++;
  m.slots[slot] = value;
}

static void MatchMachine._set_value(
  MatchMachine m, int slot, Var value, int replace_span) {
  MachineSlot data;
  memset(&data, 0, sizeof(data));
  data.kind = MACHINE_SLOT_VALUE;
  data.value = value;
  MachineSlotKind expected = replace_span ? MACHINE_SLOT_SPAN
                                          : MACHINE_SLOT_INVALID;
  if (m.slots[slot].kind != expected) {
    m._error(<slot-state>);
    return;
  }
  m._journal_slot(slot, data);
}

static void MatchMachine._set_span(
  MatchMachine m, int slot, List begin, List end, int length) {
  MachineSlot data;
  memset(&data, 0, sizeof(data));
  data.kind = MACHINE_SLOT_SPAN;
  data.span.begin = begin;
  data.span.end = end;
  data.span.length = length;
  if (m.stats) m.stats.span_descriptors++;
  if (m.slots[slot].kind != MACHINE_SLOT_INVALID) {
    m._error(<slot-state>);
    return;
  }
  m._journal_slot(slot, data);
}

static int MatchMachine._slot_value_equal(
  MatchMachine m, MachineSlot *slot, Var value) {
  if (slot.kind != MACHINE_SLOT_VALUE) return 0;
  return slot.value == value;
}

static int MatchMachine._push_frame(MatchMachine m) {
  if (m.fp + 1 >= MACHINE_FRAME_MAX) {
    m._error(<frame-max>);
    return 0;
  }
  MatchFrame *frame = &m.frames[m.fp++];
  frame.return_pc = m.pc;
  frame.caller_entry_undo = m.current_entry_undo;
  frame.caller_value = m.value;
  memset(&m.regs[m.fp], 0, sizeof(MachineRegs));
  m.current_entry_undo = m.undo_count;
  if (m.stats) {
    m.stats.calls++;
    if (m.fp + 1 > m.stats.max_frames) m.stats.max_frames = m.fp + 1;
  }
  return 1;
}

static void MatchMachine._pop_frame(MatchMachine m) {
  assert(m.fp > 0);
  m.fp--;
  MatchFrame *frame = &m.frames[m.fp];
  m.pc = frame.return_pc;
  m.current_entry_undo = frame.caller_entry_undo;
  m.value = frame.caller_value;
}

static void MatchMachine._return_from_call(MatchMachine m, int success) {
  if (!success) m._rollback(m.current_entry_undo);
  m.status = success ? <ok> : <fail>;
  if (m.stats) m.stats.returns++;
  m._clear_registers(m.fp);
  if (!m.fp) {
    m.running = 0;
    return;
  }
  m._pop_frame();
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
  for (int i = 0; i < m.slot_count; i++) {
    memset(&m.slots[i], 0, sizeof(MachineSlot));
    m.slots[i].kind = MACHINE_SLOT_INVALID;
  }
  memset(&m.regs[0], 0, sizeof(MachineRegs));
  if (m.stats) {
    m.stats.calls++;
    if (m.stats.max_frames < 1) m.stats.max_frames = 1;
  }
}

/* Execute one Match word and report whether another word remains. Fetch
   advances pc before dispatch, so calls save the following word and branches
   replace it. Machine invariant failures roll back all captures and store an
   error; predicates that raise can instead transfer out while the machine is
   marked running. */
int MatchMachine.step(MatchMachine m) {
  if (!m.running) return 0;
  MachineView *p = &m.program;
  const MachineWord *w = &p.code[m.pc++];
  switch (w.op) {
    case MW_EQ_VALUE_CONST: {
      int equal = w.d == MACHINE_COMPARE_BITS ?
                  m.value.u64 == p.consts[w.a].u64 :
                  m.value == p.consts[w.a];
      if (!equal) m.pc = w.target;
      break;
    }

    case MW_EQ_VALUE_BITS:
      if (m.value.u64 != p.consts[w.a].u64) m.pc = w.target;
      break;

    case MW_INPUT_LIST: if (m.value is not <list>) m.pc = w.target;
      else {
        *m._cursor(w.a) = m.value;
        *m._distance(w.a) = 0;
      }
      break;

    case MW_NONNIL:
      if (!*m._cursor(w.a)) m.pc = w.target;
      break;

    case MW_NIL:
      if (*m._cursor(w.a)) m.pc = w.target;
      break;

    case MW_CALL: {
      Var argument = m.value;
      if (w.b == MACHINE_CALL_HEAD) {
        if (!*m._cursor(w.c)) {
          m._error(<call-head>);
          break;
        }
        argument = car(*m._cursor(w.c));
      }
      else if (w.b == MACHINE_CALL_CURSOR)
        argument = *m._cursor(w.c);

      if (!m._push_frame()) break;
      m.value = argument;
      m.pc = w.a;
      break;
    }

    case MW_BR_FAIL:
      if (m.status != <ok>) m.pc = w.target;
      break;

    case MW_JUMP: m.pc = w.target;
      break;

    case MW_ADVANCE:
      if (!*m._cursor(w.a)) {
        m._error(<advance>);
        break;
      }
      *m._cursor(w.a) = cdr(*m._cursor(w.a));
      (*m._distance(w.a))++;
      break;

    case MW_ADVANCE_OPTIONAL:
      if (*m._cursor(w.a)) {
        *m._cursor(w.a) = cdr(*m._cursor(w.a));
        (*m._distance(w.a))++;
      }
      else
        *m._int_reg(w.b) = 0;

      break;

    case MW_MOVE: *m._cursor(w.a) = *m._cursor(w.b);
      *m._distance(w.a) = *m._distance(w.b);
      break;

    case MW_OFFSET:
      for (int n = 0; n < w.b && *m._cursor(w.a); n++) {
        *m._cursor(w.a) = cdr(*m._cursor(w.a));
        (*m._distance(w.a))++;
      }
      break;

    /* Enter the list at the head of cursor b through the bank's next
       register. No call frame is pushed. */
    case MW_DESCEND: {
      List at = *m._cursor(w.b);
      if (!at) {
        m.pc = w.target;
        break;
      }
      Var head = car(at);
      if (head is not <list>) {
        m.pc = w.target;
        break;
      }
      *m._cursor(w.c) = head;
      *m._distance(w.c) = 0;
      break;
    }

    /* The split and probe cursors advance in lockstep until the probe finds
       the anchor or runs off the end of the input. Both cursors and both
       distances remain visible afterward. */
    case MW_SCAN: {
      List split = *m._cursor(w.a), probe = *m._cursor(w.b);
      int split_distance = *m._distance(w.a);
      int probe_distance = *m._distance(w.b);
      Var anchor = p.consts[w.c];
      while (probe) {
        if (m.stats) m.stats.scan_cells++;
        int equal = w.d == MACHINE_COMPARE_BITS ?
                    car(probe).u64 == anchor.u64 : car(probe) == anchor;
        if (equal) break;
        split = cdr(split);
        probe = cdr(probe);
        split_distance++;
        probe_distance++;
      }
      *m._cursor(w.a) = split;
      *m._cursor(w.b) = probe;
      *m._distance(w.a) = split_distance;
      *m._distance(w.b) = probe_distance;
      if (!probe) m.pc = w.target;
      break;
    }

    case MW_SET_ACTIVE: *m._int_reg(w.a) = w.b;
      break;

    case MW_REQUIRE_ACTIVE: if (!*m._int_reg(w.a)) m.pc = w.target;
      break;

    case MW_MARK: m._mark().undo_count = m.undo_count; break;

    case MW_ROLLBACK: m._rollback(m._mark().undo_count);
      if (m.stats && w.b == MACHINE_ROLLBACK_RETRY) m.stats.retries++;
      break;

    case MW_SLOT_VALID:
      if (m.slots[w.a].kind != MACHINE_SLOT_INVALID) m.pc = w.target;
      break;

    case MW_SLOT_IS_SPAN:
      if (m.slots[w.a].kind == MACHINE_SLOT_SPAN) m.pc = w.target;
      break;

    case MW_SLOT_SET_VALUE: m._set_value(w.a, m.value, w.b);
      break;

    case MW_SLOT_SET_SPAN: {
      int length = *m._distance(w.c) - *m._distance(w.b);
      m._set_span(w.a, *m._cursor(w.b), *m._cursor(w.c), length);
      break;
    }

    case MW_SLOT_EQ_VALUE:
      if (!m._slot_value_equal(&m.slots[w.a], m.value)) m.pc = w.target;
      break;

    case MW_SLOT_EQ_PREFIX: {
      int length = *m._distance(w.c) - *m._distance(w.b);
      MachineSlot *slot = &m.slots[w.a];
      if (!slot.prefix_equal(*m._cursor(w.b), length, m.stats))
        m.pc = w.target;
      break;
    }

    case MW_SLOT_EQ_FINAL_IDENTITY: {
      MachineSlot *slot = &m.slots[w.a];
      if (!slot.final_equal(*m._cursor(w.b), m.stats)) m.pc = w.target;
      break;
    }

    case MW_CURSOR_VALUE: m.value = *m._cursor(w.a);
      if (w.b && m.stats) {
        m.stats.direct_shares++;
        m.stats.materializations_avoided++;
      }
      break;

    /* Each fused leaf-element word subsumes the NONNIL guard, the one-value
       child a CALL frame would execute against the cursor head, and the
       ADVANCE. Journal and comparison behavior matches the framed
       lowering. */
    case MW_EQ_HEAD_CONST: {
      List at = *m._cursor(w.b);
      if (!at) {
        m.pc = w.target;
        break;
      }
      int equal = w.d == MACHINE_COMPARE_BITS ?
                  car(at).u64 == p.consts[w.a].u64 :
                  car(at) == p.consts[w.a];
      if (!equal) {
        m.pc = w.target;
        break;
      }
      *m._cursor(w.b) = cdr(at);
      (*m._distance(w.b))++;
      break;
    }

    case MW_BIND_HEAD: {
      List at = *m._cursor(w.b);
      if (!at) {
        m.pc = w.target;
        break;
      }
      if (m.slots[w.a].kind == MACHINE_SLOT_INVALID) {
        m._set_value(w.a, car(at), 0);
        if (m.status == <error>) break;
      }
      else if (!m._slot_value_equal(&m.slots[w.a], car(at))) {
        m.pc = w.target;
        break;
      }
      *m._cursor(w.b) = cdr(at);
      (*m._distance(w.b))++;
      break;
    }

    case MW_SKIP_HEAD: {
      List at = *m._cursor(w.b);
      if (!at) {
        m.pc = w.target;
        break;
      }
      *m._cursor(w.b) = cdr(at);
      (*m._distance(w.b))++;
      break;
    }

    case MW_RET_SUCCESS: m._return_from_call(1);
      break;

    case MW_RET_FAILURE: m._return_from_call(0);
      break;

    case MW_TAG: {
      Symbol expected = p.consts[w.a];
      if (m.value is not expected) m.pc = w.target;
      break;
    }

    case MW_MATCH_KIND: {
      int hit = 0;
      switch (w.b) {
        case MACHINE_KIND_ATOM_BINDER: hit = m.value.is_atom_binder();
          break;
        case MACHINE_KIND_LIST_BINDER: hit = m.value.is_list_binder();
          break;
        case MACHINE_KIND_BINDER: hit = m.value.is_binder();
          break;
        case MACHINE_KIND_MATCH_OP: hit = m.value.is_match_op();
          break;
      }
      if (!hit) m.pc = w.target;
      break;
    }
    default: m._error(<bad-word>);
  }
  return m.running;
}

/* Execute Match words until success, failure, or a stored machine error. */
void MatchMachine.run(MatchMachine m) {
  while (m.step()) {}
}
// spans, cleanup, and invariants

static void MatchMachine._ensure_scratch(MatchMachine m, int length) {
  if (length <= m.scratch_capacity) return;
  int capacity = m.scratch_capacity ? m.scratch_capacity : 16;
  while (capacity < length) capacity *= 2;
  Var *grown = Scope.realloc(m.scratch, sizeof(Var) * capacity);
  m.scratch = grown;
  m.scratch_capacity = capacity;
}

/* Materialize a borrowed span. A complete suffix shares the existing
   immutable List directly, an empty span returns nil, and a proper prefix
   copies through growable machine scratch once. An invalid end stores
   <bad-span>; allocation and consing can raise. */
List MatchMachine.materialize_span(MatchMachine m, MachineSpan span) {
  if (m.stats) m.stats.materialization_requests++;
  if (!span.end) {
    if (m.stats) {
      m.stats.direct_shares++;
      m.stats.materializations_avoided++;
    }
    return span.begin;
  }
  if (!span.length) {
    if (m.stats) m.stats.materialization_completions++;
    return NULL;
  }
  m._ensure_scratch(span.length);
  List at = span.begin;
  for (int i = 0; i < span.length; i++) {
    if (!at) {
      m._error(<bad-span>);
      return NULL;
    }
    m.scratch[i] = car(at);
    at = cdr(at);
    if (m.stats) m.stats.materialized_cells++;
  }
  if (at != span.end) {
    m._error(<bad-span>);
    return NULL;
  }
  List result = NULL;
  for (int i = span.length; i; i--) {
    if (m.stats) m.stats.cons_requests++;
    result = cons(m.scratch[i - 1], result);
  }
  if (m.stats) m.stats.materialization_completions++;
  return result;
}

/* Return a stopped invocation to idle and clear its borrowed execution state.
   Reusable scratch and the optional stats pointer remain installed.

   Raises: `<bad-state>` when execution is still running. */
void MatchMachine.finish(MatchMachine m) {
  if (m.running) raise %(bad-state (owner "MatchMachine.finish"));

  for (int i = 0; i < m.slot_count; i++) {
    memset(&m.slots[i], 0, sizeof(MachineSlot));
    m.slots[i].kind = MACHINE_SLOT_INVALID;
  }
  for (int depth = 0; depth <= m.fp; depth++) m._clear_registers(depth);
  m.slot_count = 0;
  m.undo_count = 0;
  m.fp = 0;
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
