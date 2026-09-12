/*  machine.x -- shared `Match` and Lisp wordcode and execution state

    Copyright (c) 2026 Gary William Flake.

    MachineProgram holds immutable 8-byte wordcode frozen from the shared
    builder. This module also defines the separate `Match` and Lisp state and
    frame layouts read by `match-machine.x` and `lisp-machine.x`. The decoders
    share the <idle>, <running>, <ok>, <fail>, and <error> status names,
    errors, and only `MW_JUMP`. No instruction may call the recursive matcher
    or Lisp evaluator.

    `Match` stack-allocates each invocation; Lisp reuses session-scoped
    storage.
    Nested calls each keep their own state. No process-global mutable machine
    exists. Builder storage grows in the active scope with checked capacity,
    and a frozen program is one exact-sized allocation with separately counted
    header, code, constants, and metadata. Emission checks every field range
    and signed-short target, including the -1 patch placeholder. `finish`
    rejects a running machine before clearing its active state.
*/

#pragma once
#include "common.x"
#include "var.x"
#include "list.x"
#include "symbol.x"
#include "func.x"

// capacity fences

#define MACHINE_CODE_MAX     4096
#define MACHINE_CONST_MAX     256
#define MACHINE_BINDER_MAX     64
#define MACHINE_FRAME_MAX     128
#define MACHINE_UNDO_MAX      256
#define MACHINE_CURSOR_REGS     3
#define MACHINE_INT_REGS        2
#define MACHINE_VALUE_MAX     256
#define MACHINE_LOCAL_MAX     256
/* Operand slots a Lisp call leaves for the callee before crossing to the
   evaluator. A caller's live operands stay below the callee's operand base,
   so recursion consumes the value stack along with frames and locals. The
   value stack usually runs out first. */
#define MACHINE_CALL_RESERVE   64

// shared vocabulary

/* Records the result of preparing a program.

    PREPARED programs may execute, INELIGIBLE inputs use their ordinary path,
    and MALFORMED inputs must be rejected. */
typedef enum MachinePrepare {
  MACHINE_PREPARED,
  MACHINE_INELIGIBLE,
  MACHINE_MALFORMED
} MachinePrepare;

/* Names the shared Match and Lisp wordcode operations.

    A star, guard, or alternative is a template composed from these; there
    is no STAR, OR, or NOT opcode. SCAN is the one fused list-search
    instruction, and its inline NONNIL/EQ_HEAD/ADVANCE loop defines what it
    does. */
enum MachineOp {
  MW_EQ_VALUE_CONST,
  MW_EQ_VALUE_BITS,
  MW_INPUT_LIST,
  MW_NONNIL,
  MW_NIL,
  MW_CALL,
  MW_BR_FAIL,
  MW_JUMP,
  MW_ADVANCE,
  MW_ADVANCE_OPTIONAL,
  MW_MOVE,
  MW_OFFSET,
  MW_DESCEND,
  MW_SCAN,
  MW_SET_ACTIVE,
  MW_REQUIRE_ACTIVE,
  MW_MARK,
  MW_ROLLBACK,
  MW_SLOT_VALID,
  MW_SLOT_IS_SPAN,
  MW_SLOT_SET_VALUE,
  MW_SLOT_SET_SPAN,
  MW_SLOT_EQ_VALUE,
  MW_SLOT_EQ_PREFIX,
  MW_SLOT_EQ_FINAL_IDENTITY,
  MW_CURSOR_VALUE,
  MW_EQ_HEAD_CONST,
  MW_BIND_HEAD,
  MW_SKIP_HEAD,
  MW_RET_SUCCESS,
  MW_RET_FAILURE,
  MW_TAG,
  MW_MATCH_KIND,
  MW_LCONST,
  MW_LLOCAL,
  MW_LCAPTURE,
  MW_LGLOBAL,
  MW_LBR_NIL,
  MW_LPRECALL,
  MW_LCALL,
  MW_LTAILCALL,
  MW_LQQ_WRAP,
  MW_LQQ_APPEND,
  MW_LDROP,
  MW_LRETURN,
  MW_LLAMBDA,
  MW_LEXPAND
};

/* Selects the binder predicate applied by MW_MATCH_KIND. */
enum MachineMatchKind {
  MACHINE_KIND_ATOM_BINDER,
  MACHINE_KIND_LIST_BINDER,
  MACHINE_KIND_BINDER,
  MACHINE_KIND_MATCH_OP
};

/* Selects raw Var-bit or language equality for a comparison word. */
enum MachineCompare {
  MACHINE_COMPARE_BITS,
  MACHINE_COMPARE_EQUAL
};

/* Selects the value passed to a Match subprogram call. */
enum MachineCallSource {
  MACHINE_CALL_CURRENT,
  MACHINE_CALL_HEAD,
  MACHINE_CALL_CURSOR
};

/* Distinguishes ordinary restoration from a measured retry. */
enum MachineRollback {
  MACHINE_ROLLBACK_RESTORE,
  MACHINE_ROLLBACK_RETRY
};

/* Identifies the active member of a Match capture slot. */
typedef enum MachineSlotKind {
  MACHINE_SLOT_INVALID,
  MACHINE_SLOT_VALUE,
  MACHINE_SLOT_SPAN
} MachineSlotKind;

// representation

/* Stores one eight-byte machine instruction. */
typedef struct MachineWord {
  unsigned char op, b, c, d;
  short a, target;
} MachineWord;

/* Borrows code, constants, binders, counts, and an entry root.

    A builder view observes in-place target patches. Growth may invalidate its
    pointers, emissions and additions leave its counts stale, and free
    invalidates it. A frozen-program view stays valid while the program is
    allocated. */
typedef struct MachineView {
  const MachineWord *code;
  const Var *consts;
  const Atom *binders, int length, const_count, binder_count, root;
} MachineView;

/* Owns an exact-sized immutable frozen wordcode program.

    One allocation holds this header followed by aligned code, constant, and
    binder sections. The copied Var and Atom bits do not own their pointees.
    The program contains no execution state and never changes after freeze. */
typedef struct MachineProgram {
  int length, const_count, binder_count, root;
} *MachineProgram;

/* Accumulates a mutable program in the active Scope.

    The first ineligibility reason is sticky. Constants and binders are
    shallow values whose pointees must outlive any frozen program. */
typedef struct MachineBuilder {
  MachineWord *code;
  Var *consts;
  Atom binders[MACHINE_BINDER_MAX];
  int length, code_capacity, const_count, const_capacity, binder_count, root;
  MachinePrepare status, const char *reason;
} *MachineBuilder;

// execution state

/* Borrows the half-open List range from begin to end with its cell count. */
typedef struct MachineSpan {
  List begin, end, int length;
} MachineSpan;

/* Stores either one captured value or one borrowed List span.

    The value's pointee and the span's List cells are borrowed. */
typedef struct MachineSlot {
  MachineSlotKind kind;
  Var value;
  MachineSpan span;
} MachineSlot;

/* Records the prior value of one capture slot for rollback. */
typedef struct MachineUndo {
  int slot;
  MachineSlot prior;
} MachineUndo;

/* Records an undo-journal position for a later rollback. */
typedef struct MachineMark {
  int undo_count;
} MachineMark;

/* Saves a Match call's return pc, undo position, and caller value.

    MW_CALL jumps within the single view that `begin` bound. No Match opcode
    assigns `program`, and a Match frame has no caller program to restore. */
typedef struct MatchFrame {
  int return_pc, caller_entry_undo;
  Var caller_value;
} MatchFrame;

/* Saves the program, stack bases, counts, and value of a Lisp caller. */
typedef struct LispFrame {
  int return_pc, caller_operand_base, caller_local_base;
  int caller_value_count, caller_local_count;
  Var caller_value;
  MachineView caller_program;
} LispFrame;

/* Stores the cursors, integers, and journal mark for one frame depth.

    One register bank per depth means the frame pointer names the active bank
    and teardown is one clear. */
typedef struct MachineRegs {
  List cursors[MACHINE_CURSOR_REGS];
  int distances[MACHINE_CURSOR_REGS], ints[MACHINE_INT_REGS];
  MachineMark mark;
} MachineRegs;

/* Collects optional, caller-owned execution counters.

    Initialize the structure before use and keep it alive while a machine or
    Lisp session retains its pointer. Updates are not synchronized. */
typedef struct MachineStats {
  long scan_cells, retries, calls, returns;
  long range_comparisons, final_range_comparisons;
  long span_descriptors, cons_requests;
  long materialization_requests, materialization_completions;
  long materializations_avoided, materialized_cells, direct_shares;
  long local_loads, capture_loads, global_loads;
  long nil_edges, nil_taken, prepared_calls, native_calls;
  long lisp_returns;
  int max_frames;
} MachineStats;

/* Holds one caller-owned Match-machine invocation.

    Callers may stack-allocate the storage:

     struct MatchMachine storage;
     MatchMachine m = &storage;
     MatchMachine.open(m);

    `open` initializes fresh storage cheaply; `begin` binds a program and
    initializes only its binder slots. Count fields guard every array, so
    unused capacity is never touched or cleared. The program, input Lists,
    and optional stats sink must outlive execution and span materialization.
    `dispose` releases the reusable materialization scratch allocation. */
typedef struct MatchMachine {
  MachineView program;
  int pc, Symbol status, int running;
  Var value, error;
  int fp, current_entry_undo, undo_count, slot_count;
  MachineStats *stats;
  Var *scratch;
  int scratch_capacity;
  MatchFrame frames[MACHINE_FRAME_MAX];
  MachineRegs regs[MACHINE_FRAME_MAX];
  MachineSlot slots[MACHINE_BINDER_MAX];
  MachineUndo undo[MACHINE_UNDO_MAX];
} *MatchMachine;

/* Holds one caller-owned or Lisp-session-owned Lisp-machine invocation.

    The program, Lisp context, Var pointees, and optional stats sink are
    borrowed for execution; `begin` copies the argument array. A callback error
    transfer can leave the machine running. The caller must clear that flag
    before `finish` during unwinding. */
typedef struct LispMachine {
  MachineView program;
  int pc, Symbol status, int running;
  Var value, error;
  int fp, value_count, local_count, operand_base, local_base;
  void *lisp_context;
  MachineStats *stats;
  LispFrame frames[MACHINE_FRAME_MAX];
  Var values[MACHINE_VALUE_MAX];
  Var locals[MACHINE_LOCAL_MAX];
} *LispMachine;

/* Compares a captured value or span with an exact List prefix.

    VALUE slots use language equality and require an exact-length List. SPAN
    slots compare exactly `length` cells and require the stored end boundary.
    The inputs and span remain borrowed. */
inline int MachineSlot.prefix_equal(
  MachineSlot *slot, List input, int length, MachineStats *stats) {
  if (stats) stats.range_comparisons++;
  List expected, end = NULL;
  if (slot.kind == MACHINE_SLOT_VALUE) {
    expected = slot.value;
  }
  else {
    if (slot.span.length != length) return 0;
    expected = slot.span.begin;
    end = slot.span.end;
  }
  for (int n = 0; n < length; n++) {
    if (!input || !expected || !(car(input) == car(expected))) return 0;
    input = cdr(input);
    expected = cdr(expected);
  }
  return slot.kind == MACHINE_SLOT_SPAN ? expected == end : !expected;
}

/* Compares a captured value or span with an exact final List by identity.

    VALUE slots require List pointer identity. SPAN slots use raw element
    identity and the exact range boundary. Interned consing can make a
    materialized interior prefix identical to an existing suffix, and a
    successful instruction then memoizes that suffix as VALUE. */
inline int MachineSlot.final_equal(
  MachineSlot *slot, List input, MachineStats *stats) {
  if (slot.kind == MACHINE_SLOT_VALUE) {
    List value = slot.value;
    return value == input;
  }
  if (stats) {
    stats.range_comparisons++;
    stats.final_range_comparisons++;
  }
  List expected = slot.span.begin, candidate = input, int length = 0;
  while (length < slot.span.length && expected != slot.span.end && candidate) {
    if (car(expected).u64 != car(candidate).u64) return 0;
    expected = cdr(expected);
    candidate = cdr(candidate);
    length++;
  }
  return length == slot.span.length && expected == slot.span.end && !candidate;
}

protocol Cleanup(MachineBuilder);

#pragma private

#include <string.h>
#include "scope.x"
#include "exception.x"

// builder

static int MachineBuilder._fail(MachineBuilder b, const char *reason) {
  if (b.status == MACHINE_PREPARED) {
    b.status = MACHINE_INELIGIBLE;
    b.reason = reason;
  }
  return -1;
}

/* Allocate a prepared builder in the active Scope with no root selected. */
MachineBuilder MachineBuilder.new(void) {
  MachineBuilder b = Scope.calloc(1, sizeof(struct MachineBuilder));
  b.status = MACHINE_PREPARED;
  b.reason = "prepared";
  b.root = -1;
  return b;
}

/* Free the builder's mutable arrays and the builder itself. Any builder view
   becomes invalid; constant and binder pointees are not freed. */
void MachineBuilder.free(MachineBuilder b) {
  if (!b) return;
  if (b.code) Scope.free(b.code);
  if (b.consts) Scope.free(b.consts);
  Scope.free(b);
}

static int MachineBuilder._grow_code(MachineBuilder b) {
  if (b.length < b.code_capacity) return 1;
  if (b.code_capacity >= MACHINE_CODE_MAX)
    return b._fail("code-capacity") + 1;
  int capacity = b.code_capacity ? b.code_capacity * 2 : 64;
  if (capacity > MACHINE_CODE_MAX) capacity = MACHINE_CODE_MAX;
  MachineWord *grown = Scope.realloc(b.code, sizeof(MachineWord) * capacity);
  b.code = grown;
  b.code_capacity = capacity;
  return 1;
}

/* Append one range-checked instruction and return its site. The opcode need
   only fit in a byte; a decoder reports unsupported words. A failed builder
   keeps its first reason and all later emissions return -1. Allocation can
   raise. */
int MachineBuilder.emit(
  MachineBuilder b, int op, int a, int operand_b, int c, int d, int target) {
  if (b.status != MACHINE_PREPARED || !b._grow_code()) return -1;
  if (op < 0 || op > 255 || operand_b < 0 || operand_b > 255 ||
      c < 0 || c > 255 || d < 0 || d > 255 ||
      a < -1 || a >= MACHINE_CODE_MAX ||
      target < -1 || target >= MACHINE_CODE_MAX)
    return b._fail("instruction-range");
  MachineWord word;
  word.op = op;
  word.b = operand_b;
  word.c = c;
  word.d = d;
  word.a = a;
  word.target = target;
  b.code[b.length] = word;
  return b.length++;
}

/* Intern a constant by raw Var bits and return its byte-sized index. The
   stored value is shallow; capacity failure makes the builder ineligible. */
int MachineBuilder.constant(MachineBuilder b, Var value) {
  if (b.status != MACHINE_PREPARED) return -1;
  for (int i = 0; i < b.const_count; i++)
    if (b.consts[i].u64 == value.u64) return i;
  if (b.const_count >= b.const_capacity) {
    if (b.const_capacity >= MACHINE_CONST_MAX)
      return b._fail("constant-capacity");
    int capacity = b.const_capacity ? b.const_capacity * 2 : 16;
    if (capacity > MACHINE_CONST_MAX) capacity = MACHINE_CONST_MAX;
    Var *grown = Scope.realloc(b.consts, sizeof(Var) * capacity);
    b.consts = grown;
    b.const_capacity = capacity;
  }
  b.consts[b.const_count] = value;
  return b.const_count++;
}

/* Intern a binder by raw Atom bits and return its fixed-table index. */
int MachineBuilder.binder(MachineBuilder b, Atom binder) {
  if (b.status != MACHINE_PREPARED) return -1;
  for (int i = 0; i < b.binder_count; i++)
    if (b.binders[i].u64 == binder.u64) return i;
  if (b.binder_count >= MACHINE_BINDER_MAX)
    return b._fail("binder-capacity");
  b.binders[b.binder_count] = binder;
  return b.binder_count++;
}

/* Set a nonnegative instruction site's branch target; a negative site is a
   no-op placeholder. The site must name emitted code.

   Raises: `<bad-arg>` when target is outside the code domain. The failure
   leaves the patch site unchanged. */
void MachineBuilder.set_target(MachineBuilder b, int site, int target) {
  if (target < 0 || target >= MACHINE_CODE_MAX)
    raise %(bad-arg (owner "MachineBuilder.set_target") (target $target));

  if (site >= 0) b.code[site].target = target;
}

/* Apply one validated target to the listed patch sites in order. Negative
   sites are ignored; each nonnegative site must name emitted code. */
void MachineBuilder.patch(
  MachineBuilder b, int *sites, int count, int target) {
  if (target < 0 || target >= MACHINE_CODE_MAX) b.set_target(-1, target);
  for (int i = 0; i < count; i++)
    MachineBuilder.set_target(b, sites[i], target);
}

/* Borrow the builder's current arrays and counts. Emission and constant or
   binder additions make the counts stale, growth can invalidate pointers,
   target patching changes the observed words, and free invalidates all
   pointers. */
MachineView MachineBuilder.view(MachineBuilder b) {
  MachineView view = {
    b.code, b.consts, b.binders,
    b.length, b.const_count, b.binder_count, b.root
  };
  return view;
}

// immutable programs

static size_t _program_bytes(
  int length, int const_count, int binder_count) =>
    sizeof(struct MachineProgram) + sizeof(MachineWord) * length +
         sizeof(Var) * const_count + sizeof(Atom) * binder_count;

/* Borrow a frozen program's packed sections until the program is freed. */
MachineView MachineProgram.view(MachineProgram program) {
  const MachineWord *code = (const MachineWord *) (program + 1);
  const Var *consts = (const Var *) (code + program.length);
  const Atom *binders = (const Atom *) (consts + program.const_count);
  MachineView view = {
    code, consts, binders,
    program.length, program.const_count, program.binder_count,
    program.root
  };
  return view;
}

/* Return the exact byte size of the program's single packed allocation. */
size_t MachineProgram.bytes(MachineProgram program) => _program_bytes(
    program.length, program.const_count, program.binder_count);

/* Copy a prepared builder with a selected root into one immutable Scope
   allocation. Return null for an ineligible or rootless builder. The producer
   must make root name emitted code; freeze only checks that it is
   nonnegative. */
MachineProgram MachineBuilder.freeze(MachineBuilder b) {
  if (b.status != MACHINE_PREPARED || b.root < 0) return NULL;
  size_t bytes = _program_bytes(
    b.length, b.const_count, b.binder_count);

  MachineProgram program = Scope.malloc(bytes);
  program.length = b.length;
  program.const_count = b.const_count;
  program.binder_count = b.binder_count;
  program.root = b.root;
  MachineWord *code = (MachineWord *) (program + 1);
  Var *consts = (Var *) (code + b.length);
  Atom *binders = (Atom *) (consts + b.const_count);
  if (b.length) memcpy(code, b.code, sizeof(MachineWord) * b.length);
  if (b.const_count) memcpy(consts, b.consts, sizeof(Var) * b.const_count);
  if (b.binder_count)
    memcpy(binders, b.binders, sizeof(Atom) * b.binder_count);
  return program;
}

/* Free a frozen program and invalidate every view borrowed from it. */
void MachineProgram.free(MachineProgram program) {
  if (program) Scope.free(program);
}

/* Ends the owned lifetime when a managed local leaves its block. */
void MachineBuilder.cleanup(MachineBuilder value) { value.free(); }
