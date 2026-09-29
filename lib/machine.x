/*  machine.x -- `Match` wordcode and execution state

    Copyright (c) 2026 Gary William Flake.

    MachineBuilder emits range-checked 8-byte words and freezes them into one
    exact-sized, immutable MachineProgram allocation. This module also
    defines the `Match` invocation state and frame layouts that
    `match-machine.x` reads. `Match` stack-allocates each invocation, so
    nested matches keep separate state and no process-global machine exists.
    The decoder uses the <idle>, <running>, <ok>, <fail>, and <error> status
    names, and no instruction calls the recursive matcher.
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

// vocabulary

/* Records the result of preparing a program.

    PREPARED programs may execute, INELIGIBLE inputs use their ordinary path,
    and MALFORMED inputs must be rejected. */
typedef enum MachinePrepare {
  MACHINE_PREPARED,
  MACHINE_INELIGIBLE,
  MACHINE_MALFORMED
} MachinePrepare;

/* Names the Match wordcode operations.

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
  MW_MATCH_KIND
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
class MachineProgram struct {
  int length, const_count, binder_count, root;
} *;

/* Accumulates a mutable program in the active Scope.

    The first ineligibility reason is sticky. Constants and binders are
    shallow values whose pointees must outlive any frozen program. */
class MachineBuilder struct {
  MachineWord *code;
  Var *consts;
  Atom binders[MACHINE_BINDER_MAX];
  int length, code_capacity, const_count, const_capacity, binder_count, root;
  MachinePrepare status, const char *reason;
} *;

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

/* Stores the cursors, integers, and journal mark for one frame depth.

    One register bank per depth means the frame pointer names the active bank
    and teardown is one clear. */
typedef struct MachineRegs {
  List cursors[MACHINE_CURSOR_REGS];
  int distances[MACHINE_CURSOR_REGS], ints[MACHINE_INT_REGS];
  MachineMark mark;
} MachineRegs;

/* Collects optional, caller-owned execution counters.

    Initialize the structure before use and keep it alive while a machine
    retains its pointer. Updates are not synchronized. */
typedef struct MachineStats {
  long scan_cells, retries, calls, returns;
  long range_comparisons, final_range_comparisons;
  long span_descriptors, cons_requests;
  long materialization_requests, materialization_completions;
  long materializations_avoided, materialized_cells, direct_shares;
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
  // An optional relation replaces plain equality when a repeated binder is
  // compared, for value slots and for prefix or final sequence slots.
  int (*relation)(void *, int, Var, Var, void *);
  void *relation_context;
  // An optional view gives the value a list pattern examines when the
  // machine enters an element; captures keep the element itself.
  Var (*view)(Var);
  Var *scratch;
  int scratch_capacity;
  MatchFrame frames[MACHINE_FRAME_MAX];
  MachineRegs regs[MACHINE_FRAME_MAX];
  MachineSlot slots[MACHINE_BINDER_MAX];
  MachineUndo undo[MACHINE_UNDO_MAX];
} *MatchMachine;

/* Compares a captured value or span with an exact List prefix.

    VALUE slots use language equality and require an exact-length List. SPAN
    slots compare exactly `length` cells and require the stored end boundary.
    The inputs and span remain borrowed. */
inline int MachineSlot.prefix_equal(
  MachineSlot *slot, List input, int length, MachineStats *stats) {
  if (stats) stats.range_comparisons++;
  List expected, end = NULL;
  if (slot.kind == MACHINE_SLOT_VALUE) expected = slot.value;
  else {
    if (slot.span.length != length) return 0;
    expected = slot.span.begin;
    end = slot.span.end;
  }
  for (int n = 0; n < length; n++) {
    if (!input || !expected || !(input.car() == expected.car())) return 0;
    input = input.cdr();
    expected = expected.cdr();
  }
  return slot.kind == MACHINE_SLOT_SPAN ? expected == end : !expected;
}

/* Compares a captured value or span with an exact final List.

    A repeated binder means equal values, so both kinds use language equality
    on each element, as `prefix_equal` does. SPAN slots also require the exact
    range boundary. Interned consing can make a materialized interior prefix
    identical to an existing suffix, and a successful instruction then
    memoizes that suffix as VALUE. */
inline int MachineSlot.final_equal(
  MachineSlot *slot, List input, MachineStats *stats) {
  if (slot.kind == MACHINE_SLOT_VALUE) {
    List expected = slot.value;
    if (expected == input) return 1;
    while (expected && input) {
      if (!(expected.car() == input.car())) return 0;
      expected = expected.cdr();
      input = input.cdr();
    }
    return !expected && !input;
  }
  if (stats) {
    stats.range_comparisons++;
    stats.final_range_comparisons++;
  }
  List expected = slot.span.begin, candidate = input, int length = 0;
  while (length < slot.span.length && expected != slot.span.end && candidate) {
    if (!(expected.car() == candidate.car())) return 0;
    expected = expected.cdr();
    candidate = candidate.cdr();
    length++;
  }
  return length == slot.span.length && expected == slot.span.end && !candidate;
}

#pragma private

#include <string.h>
#include "scope.x"
#include "exception.x"

// builder

/* Append one range-checked instruction and return its site. The opcode need
   only fit in a byte; a decoder reports unsupported words. `a` and `target`
   may be -1, the patch placeholder. A failed builder keeps its first reason
   and all later emissions return -1. Allocation can raise. */
int MachineBuilder.emit(
  MachineBuilder b, int op, int a, int operand_b, int c, int d, int target) {
  if (b.status != MACHINE_PREPARED || b._grow_code() < 0) return -1;
  if (op < 0 || op > 255 || operand_b < 0 || operand_b > 255 ||
      c < 0 || c > 255 || d < 0 || d > 255 ||
      a < -1 || a >= MACHINE_CODE_MAX ||
      target < -1 || target >= MACHINE_CODE_MAX)
    return b._fail("instruction-range");
  b.code[b.length] = (MachineWord) {
    .op = op, .b = operand_b, .c = c, .d = d, .a = a, .target = target};
  return b.length++;
}

/* Makes room for one more word, or fails the builder at MACHINE_CODE_MAX. */
static int MachineBuilder._grow_code(MachineBuilder b) {
  if (b.length < b.code_capacity) return 0;
  if (b.code_capacity >= MACHINE_CODE_MAX) return b._fail("code-capacity");
  int capacity = b.code_capacity ? b.code_capacity * 2 : 64;
  if (capacity > MACHINE_CODE_MAX) capacity = MACHINE_CODE_MAX;
  MachineWord *grown = Scope.realloc(b.code, sizeof(MachineWord) * capacity);
  b.code = grown;
  b.code_capacity = capacity;
  return 0;
}

/* Intern a constant by raw Var bits and return its byte-sized index. The
   stored value is shallow; capacity failure makes the builder ineligible. */
int MachineBuilder.constant(MachineBuilder b, Var value) {
  if (b.status != MACHINE_PREPARED) return -1;
  for (int i = 0; i < b.const_count; i++)
    if (b.consts[i].u64 == value.u64) return i;
  if (b._grow_consts() < 0) return -1;
  b.consts[b.const_count] = value;
  return b.const_count++;
}

/* Makes room for one more constant, or fails the builder at
   MACHINE_CONST_MAX. */
static int MachineBuilder._grow_consts(MachineBuilder b) {
  if (b.const_count < b.const_capacity) return 0;
  if (b.const_capacity >= MACHINE_CONST_MAX)
    return b._fail("constant-capacity");
  int capacity = b.const_capacity ? b.const_capacity * 2 : 16;
  if (capacity > MACHINE_CONST_MAX) capacity = MACHINE_CONST_MAX;
  Var *grown = Scope.realloc(b.consts, sizeof(Var) * capacity);
  b.consts = grown;
  b.const_capacity = capacity;
  return 0;
}

/* Intern a binder by raw Atom bits and return its fixed-table index. */
int MachineBuilder.binder(MachineBuilder b, Atom binder) {
  if (b.status != MACHINE_PREPARED) return -1;
  for (int i = 0; i < b.binder_count; i++)
    if (b.binders[i].u64 == binder.u64) return i;
  if (b.binder_count >= MACHINE_BINDER_MAX) return b._fail("binder-capacity");
  b.binders[b.binder_count] = binder;
  return b.binder_count++;
}

/* Set a nonnegative instruction site's branch target; a negative site is a
   no-op placeholder. The site must name emitted code. A target at the word
   after full code fails the builder with `code-capacity` instead.

   Raises: `<bad-arg>` when target is otherwise outside the code domain. A
   failure leaves the patch site unchanged. */
void MachineBuilder.set_target(MachineBuilder b, int site, int target) {
  if (target == b.length && b.length == MACHINE_CODE_MAX)
    b._fail("code-capacity");
  else if (target < 0 || target >= MACHINE_CODE_MAX)
    raise %(bad-arg (owner "MachineBuilder.set_target") (target $target));
  else if (site >= 0)
    b.code[site].target = target;
}

/* Apply one validated target to the listed patch sites in order. Negative
   sites are ignored; each nonnegative site must name emitted code. An
   invalid target raises even when `count` is zero. */
void MachineBuilder.patch(
  MachineBuilder b, int *sites, int count, int target) {
  if (target < 0 || target >= MACHINE_CODE_MAX) b.set_target(-1, target);
  for (int i = 0; i < count; i++) b.set_target(sites[i], target);
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

static int MachineBuilder._fail(MachineBuilder b, const char *reason) {
  if (b.status == MACHINE_PREPARED) {
    b.status = MACHINE_INELIGIBLE;
    b.reason = reason;
  }
  return -1;
}

// immutable programs

/* Copy a prepared builder with a selected root into one immutable Scope
   allocation. Return null for an ineligible or rootless builder. The producer
   must make root name emitted code; freeze only checks that it is
   nonnegative. */
MachineProgram MachineBuilder.freeze(MachineBuilder b) {
  if (b.status != MACHINE_PREPARED || b.root < 0) return NULL;
  size_t bytes = _program_bytes(b.length, b.const_count, b.binder_count);
  MachineProgram program = Scope.malloc(bytes);
  *program = (struct MachineProgram) {
    .length = b.length, .const_count = b.const_count,
    .binder_count = b.binder_count, .root = b.root};
  MachineWord *code = (MachineWord *) (program + 1);
  Var *consts = (Var *) (code + b.length);
  Atom *binders = (Atom *) (consts + b.const_count);
  if (b.length) memcpy(code, b.code, sizeof(MachineWord) * b.length);
  if (b.const_count) memcpy(consts, b.consts, sizeof(Var) * b.const_count);
  if (b.binder_count)
    memcpy(binders, b.binders, sizeof(Atom) * b.binder_count);
  return program;
}

static size_t _program_bytes(int length, int const_count, int binder_count) =>
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

// lifecycle

/* Prepare a builder in the active Scope with no root selected. */
void MachineBuilder.init(MachineBuilder b) {
  b.status = MACHINE_PREPARED;
  b.reason = "prepared";
  b.root = -1;
}

/* Free the builder's mutable arrays when the builder is freed. Any builder
   view becomes invalid; constant and binder pointees are not freed. */
void MachineBuilder.drop(MachineBuilder b) {
  Scope.free(b.code);
  Scope.free(b.consts);
}
