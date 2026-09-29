/*  match.x -- pattern matching and transformation utilities for lists

    Copyright (c) 2025 Gary William Flake

    A MatchPlan is the prepared form of one pattern: its capture layout and
    a program in the wordcode of `machine.x`. A plan owns both and borrows the
    canonical values in its pattern. Core matching runs only prepared plans;
    `unittest/match-recursive.x` is the reference matcher of the differential
    tests. An invocation commits captures to caller-owned storage only after
    the whole match succeeds.

    Association-List results are published from committed captures. New
    Lists canonicalize through the active pool chain; a result may belong to
    an ancestor and lives until its owning pool is released.
 */

#pragma once

$(import "error-macros.xmacro")
$(import "private-keywords.xmacro")
#include "common.x"
#include "machine.x"

/** Describes the canonical binder slots and preparation status of a pattern.
    `binders` points into the layout allocation and lists each distinct named
    binder in lexical preorder. `definite` and `possible` select those slots.
    `normalized` and the binder `Atom`s are borrowed canonical values. The
    caller owns the layout returned by `MatchCaptureLayout.analyze` and must
    free it before those values or its allocating `Scope` expire.
*/
typedef struct MatchCaptureLayout {
  Atom *binders;
  Var normalized;
  unsigned long definite, possible;
  int binder_count, MachinePrepare status, const char *reason;
} *MatchCaptureLayout;

/** Supplies caller-owned positional storage for one `Match` invocation.
    `values` has `capacity` elements. On success `present` identifies the
    elements `Match` wrote; presence is separate from a captured `void` value.
    A miss or error leaves `values` and `present` unchanged. Captured values
    are borrowed and keep their ordinary `Var`, `List`, and pool lifetimes.
*/
typedef struct MatchCaptureBuffer {
  Var *values;
  unsigned long present;
  int capacity;
} MatchCaptureBuffer;

/** Holds one reusable immutable compiled `Match` pattern.
    A prepared plan owns `program` and `layout`; malformed and ineligible plans
    have no executable program and retain their categorized `status` and
    static `reason`. Pattern constants are borrowed, so the caller must free
    the plan before their canonical pools or other owners expire.
*/
typedef struct MatchPlan {
  MachineProgram program;
  MatchCaptureLayout layout;
  MachinePrepare status, const char *reason;
} *MatchPlan;

/** Stores the process-lifetime plan for one compiler-emitted `Match` site.
    The object must be zero-initialized static storage. Its first admissible
    pattern binds it permanently; `Match` shutdown frees the plan and clears
    the site. Direct callers must not reuse a site for another pattern.
*/
typedef struct MatchCaptureSite {
  MatchPlan plan;
  int refused;
} MatchCaptureSite;

/** Cache pressure is the acquire status beyond MachinePrepare: every slot is
    leased, so none can be recycled.
*/
#define MATCH_CACHE_PRESSURE 3

/** Names an explicit cache of immutable prepared Match plans.
    A cache is not synchronized. Its caller must serialize access, keep every
    admitted pattern value alive until disposal, and dispose it when no lease
    remains active.
*/
typedef struct MatchCache *MatchCache;

/** Represents one acquired use of a cached or transient Match plan.
    A cached lease pins its entry; a transient lease owns its plan. Initialize
    it only through `MatchCache.acquire` and call `MatchLease.release` on every
    non-transferring path, including a pressure result.
*/
typedef struct MatchLease {
  MatchCache cache;
  MatchPlan transient_plan;
  unsigned long generation;
  int slot, active;
} MatchLease;

#pragma private

#include <pthread.h>
#include <stdlib.h>
#include <stddef.h>
#include <assert.h>
#include "var.x"
#include "list.x"
#include "atom.x"
#include "exception.x"
#include "symbol.x"
#include "scope.x"
#include "block.x"
#include "match-machine.x"
#include "scan.x"

/* pattern vocabulary

   A binder is `?` or `*`, alone or followed by an ASCII identifier: `?`
   binds one element and `*` a sequence. A guard operator is one of the
   compact Symbols `!is`, `!set`, `!or`, `!and`, `!not`, and `!quote`. */

/** Reports whether `atom` is a valid named or anonymous `?` binder.
    Raises: `<alloc-fail>` while decoding a compact `Atom`.
*/
meta native int Var.is_atom_binder(Var atom) => _binder_kind(atom) == '?';

/** Reports whether `atom` is a valid named or anonymous `*` binder.
    Raises: `<alloc-fail>` while decoding a compact `Atom`.
*/
meta native int Var.is_list_binder(Var atom) => _binder_kind(atom) == '*';

/** Reports whether `atom` is either valid `Match` binder form.
    Raises: `<alloc-fail>` while decoding a compact `Atom`.
*/
meta native int Var.is_binder(Var atom) => _binder_kind(atom) != 0;

/** Reports whether `atom` is a compact built-in `Match` guard operator. */
meta native int Var.is_match_op(Var atom) {
  if (atom is not <symbol>) return 0;
  Symbol symbol = atom;
  switch (symbol) {
    case <!is>: case <!set>: case <!or>: case <!and>: case <!not>:
    case <!quote>:
      return 1;
  }
  return 0;
}

/* The binder's sigil, or 0 when `atom` spells no binder. */
static int _binder_kind(Var atom) {
  if (!atom.is_atom()) return 0;
  String spelling = atom.str(), int length = spelling.len();
  if (!length) return 0;
  char sigil = spelling[0];
  if (sigil != '?' && sigil != '*') return 0;
  if (length == 1) return sigil;
  unsigned char first = (unsigned char) spelling[1];
  if (!scan_ascii_alpha(first) && first != '_') return 0;
  for (int i = 2; i < length; i++) {
    unsigned char ch = (unsigned char) spelling[i];
    if (!scan_ascii_alpha(ch) && !scan_ascii_digit(ch) && ch != '_') return 0;
  }
  return sigil;
}

static int _named_binder(Var value) =>
  value.is_binder() && value != <?> && value != <*>;

/* A compact matcher predicate, which is control vocabulary as the final
   operand of `!is`. */
static int _reserved_predicate(Var atom) =>
  atom is <symbol> &&
  (atom == <?binder?> || atom == <*binder?> || atom == <!op?>);

/* A sigil-leading `Atom` that spells no binder. */
static int _malformed_binder(Var atom) =>
  atom.is_atom() && (Atom.first(atom) == '?' || Atom.first(atom) == '*') &&
  !atom.is_binder();

/* pattern normalization

   Every guard except `!quote` accepts a leading binder when an operand
   follows it. `(OP BINDER PAT ...)` normalizes to
   `(!set BINDER (OP PAT ...))`, so a binder captures the same value in
   either spelling. The matcher is based on Peter Norvig's implementation at
   https://github.com/norvig/paip-lisp/blob/main/lisp/patmatch.lisp. */

static List _normalize_pattern(List pattern) {
  if (!pattern || pattern.car() == <!quote>) return pattern;
  List normalized = _normalize_elements(pattern);
  Var op = normalized.car();
  List args = normalized.cdr();
  if (!op.is_match_op() || op == <!quote> || !args) return normalized;
  Var binder = args.car();
  List rest = args.cdr();
  // `(!set BINDER PAT)` is the form this produces, so leave it alone
  if (!binder.is_binder() || !rest || (op == <!set> && !rest.cdr()))
    return normalized;
  return %(!set $binder ${_normalize_pattern(%($op @rest))});
}

/* Normalizes each nested pattern, keeping `elements` when none changes. */
static List _normalize_elements(List elements) {
  if (!elements) return NULL;
  Var head = elements.car(), normalized_head = head;
  if (head is <list>) normalized_head = _normalize_pattern(head);
  List tail = elements.cdr(), normalized_tail = _normalize_elements(tail);
  if (normalized_head == head && normalized_tail == tail) return elements;
  return %($normalized_head @normalized_tail);
}

/* capture layouts

   A layout gives each distinct named binder a slot in lexical preorder. A
   sigil-leading `Atom` that spells no binder, a leading `*` binder inside a
   guard, or more than MACHINE_BINDER_MAX binders makes a pattern MALFORMED,
   and its layout has no slots. */

typedef struct MatchLayoutBuilder {
  Atom binders[MACHINE_BINDER_MAX];
  int count, malformed_binder, leading_list_binder, past_capacity;
} MatchLayoutBuilder;

/* The slots a pattern binds on every match and on some match. */
typedef struct MatchSlots { unsigned long definite, possible; } MatchSlots;

/** Analyzes one `Match` pattern into its canonical positional layout.
    Distinct named binders receive slots in lexical preorder. `!quote` is
    opaque; alternatives contribute possible binders, while only binders in
    every alternative are definite. The caller owns the returned layout,
    including when `status` is `MACHINE_MALFORMED`.
    Raises: `<alloc-fail>` while normalizing or allocating the layout.
*/
MatchCaptureLayout MatchCaptureLayout.analyze(Var pattern) {
  MatchLayoutBuilder builder = {0};
  builder._collect(pattern);
  const char *malformed = builder._malformed();
  Var normalized = pattern;
  if (malformed) builder.count = 0;
  else if (pattern is <list>) normalized = _normalize_pattern(pattern);
  MatchCaptureLayout layout = builder._layout(normalized, malformed);
  // a binder-free pattern has nothing to report as definite or possible
  if (!malformed && builder.count) {
    MatchSlots slots = _pattern_slots(layout, pattern);
    layout.definite = slots.definite;
    layout.possible = slots.possible;
  }
  return layout;
}

/* Collects the raw pattern's named binders in one lexical preorder walk and
   notes each malformation. `!quote` is opaque. Compact matcher predicates
   are control vocabulary only as the final operand of `!is`. The compiler's
   dynamic-value marker retains binders in its literal children without
   treating the marker as data. */
static void MatchLayoutBuilder._collect(MatchLayoutBuilder *b, Var pattern) {
  if (pattern is not <list>) {
    b._atom(pattern);
    return;
  }
  if (pattern.is_nil()) return;
  List list = pattern;
  Var head = list.car();
  if (head == <!quote>) return;
  if (head.is_match_op()) {
    List args = list.cdr();
    if (args && args.car().is_list_binder()) b.leading_list_binder = 1;
  }
  List parts = head == <x2c-dyn> ? list.cdr() : list;
  int predicate_form = head == <!is>;
  for (List at = parts; at; at = at.cdr()) {
    Var part = at.car();
    if (predicate_form && !at.cdr() && _reserved_predicate(part)) continue;
    b._collect(part);
    if (b.malformed_binder) return;
  }
}

/* A sigil-leading `Atom` must spell a binder; a named binder takes a slot. */
static void MatchLayoutBuilder._atom(MatchLayoutBuilder *b, Var atom) {
  if (_malformed_binder(atom)) b.malformed_binder = 1;
  else if (_named_binder(atom) && b._add(atom) < 0) b.past_capacity = 1;
}

/* Returns the slot for `binder`, or -1 once the pattern is past capacity. */
static int MatchLayoutBuilder._add(MatchLayoutBuilder *b, Atom binder) {
  for (int i = 0; i < b.count; i++)
    if (b.binders[i].u64 == binder.u64) return i;
  if (b.count >= MACHINE_BINDER_MAX) return -1;
  b.binders[b.count] = binder;
  return b.count++;
}

/* The first malformation the walk noted, or NULL. */
static const char *MatchLayoutBuilder._malformed(MatchLayoutBuilder *b) {
  if (b.malformed_binder) return "binder-name";
  if (b.leading_list_binder) return "leading-list-binder-in-guard";
  if (b.past_capacity) return "binder-capacity";
  return NULL;
}

/* One allocation holds the layout and its binder table. */
static MatchCaptureLayout MatchLayoutBuilder._layout(
  MatchLayoutBuilder *b, Var normalized, const char *malformed) {
  size_t bytes = sizeof(struct MatchCaptureLayout) + sizeof(Atom) * b.count;
  MatchCaptureLayout layout = Scope.calloc(1, bytes);
  layout.binders =
    (Atom *) ((char *) layout + sizeof(struct MatchCaptureLayout));
  layout.binder_count = b.count;
  layout.status = malformed ? MACHINE_MALFORMED : MACHINE_PREPARED;
  layout.reason = malformed ? malformed : "prepared";
  layout.normalized = normalized;
  if (b.count) memcpy(layout.binders, b.binders, sizeof(Atom) * b.count);
  return layout;
}

/* definite and possible slots

   A pattern binds its definite slots on every match and its possible slots
   on some match. Analysis reads the raw pattern: a leading binder captures
   its guard, as `_normalize_pattern` reads it. */

static MatchSlots _pattern_slots(MatchCaptureLayout layout, Var pattern) {
  if (_named_binder(pattern)) return _binder_slot(layout, pattern);
  if (pattern is not <list> || pattern.is_nil()) return (MatchSlots) {0, 0};
  List list = pattern;
  Var head = list.car();
  List args = list.cdr();
  if (head == <!quote>) return (MatchSlots) {0, 0};
  if (head == <x2c-dyn>)
    return (MatchSlots) {0, _sequence_slots(layout, args).possible};
  if (!head.is_match_op()) return _sequence_slots(layout, list);
  return _guard_slots(layout, head, args);
}

/* `(!set BINDER PAT)` is the one-operand capture form, and a negation
   binds nothing on every match. */
static MatchSlots _guard_slots(MatchCaptureLayout layout, Var op, List args) {
  MatchSlots slots = {0, 0};
  if (args && args.cdr() && _named_binder(args.car())) {
    slots = _binder_slot(layout, args.car());
    args = args.cdr();
  }
  if (op == <!and>) return _union(slots, _sequence_slots(layout, args));
  if (op == <!not>) {
    MatchSlots operands = _sequence_slots(layout, args);
    return (MatchSlots) {0, slots.possible | operands.possible};
  }
  if (op == <!set> && args.len() == 1)
    return _union(slots, _sequence_slots(layout, args));
  if (op == <!or> || op == <!set>)
    return _union(slots, _choice_slots(layout, args));
  return slots;
}

/* Every element of a sequence matches, so each one's definite slots are
   definite. */
static MatchSlots _sequence_slots(MatchCaptureLayout layout, List patterns) {
  MatchSlots slots = {0, 0};
  foreach (Var pattern, patterns)
    slots = _union(slots, _pattern_slots(layout, pattern));
  return slots;
}

/* One alternative matches, so only the slots every one binds are
   definite. */
static MatchSlots _choice_slots(MatchCaptureLayout layout, List patterns) {
  MatchSlots slots = {0, 0};
  int first = 1;
  foreach (Var pattern, patterns) {
    MatchSlots part = _pattern_slots(layout, pattern);
    slots.possible |= part.possible;
    slots.definite = first ? part.definite : slots.definite & part.definite;
    first = 0;
  }
  return slots;
}

static MatchSlots _binder_slot(MatchCaptureLayout layout, Var binder) {
  int index = _layout_index(layout, binder);
  assert(index >= 0);
  unsigned long bit = 1UL << index;
  return (MatchSlots) {bit, bit};
}

static MatchSlots _union(MatchSlots a, MatchSlots b) =>
  (MatchSlots) {a.definite | b.definite, a.possible | b.possible};

static int _layout_index(MatchCaptureLayout layout, Atom binder) {
  for (int i = 0; i < layout.binder_count; i++)
    if (layout.binders[i].u64 == binder.u64) return i;
  return -1;
}

// layout queries

/** Releases one canonical `Match` capture layout.
    A null layout is ignored; every alias is invalid afterward.
*/
void MatchCaptureLayout.free(MatchCaptureLayout layout) {
  if (layout) Scope.free(layout);
}

/** Returns definite binders in canonical positional order.
    A null layout or no definite binders returns `nil`. The canonical result
    follows the module pool-chain lifetime above.
    Raises: `<alloc-fail>` while constructing the `List`.
*/
List MatchCaptureLayout.definite_list(MatchCaptureLayout layout) =>
  layout ? _binder_list(layout, layout.definite) : NULL;

/** Returns possible binders in canonical positional order.
    A null layout or no possible binders returns `nil`. The canonical result
    follows the module pool-chain lifetime above.
    Raises: `<alloc-fail>` while constructing the `List`.
*/
List MatchCaptureLayout.possible_list(MatchCaptureLayout layout) =>
  layout ? _binder_list(layout, layout.possible) : NULL;

/* The binders of the `included` slots, in slot order. */
static List _binder_list(MatchCaptureLayout layout, unsigned long included) {
  List binders = NULL;
  for (int i = layout.binder_count - 1; i >= 0; i--)
    if (_capture_bit(included, i)) binders = cons(layout.binders[i], binders);
  return binders;
}

/** Returns the canonical slot for `binder`, or -1 when it is absent.
    A null layout returns -1. Comparison uses exact `Atom` identity.
*/
int MatchCaptureLayout.index(MatchCaptureLayout layout, Atom binder) =>
  layout ? _layout_index(layout, binder) : -1;

/** Reports whether a committed capture slot is present.
    A null buffer or an index outside its capacity or `Match`'s binder limit
    returns false. Presence is independent of the captured `Var` value.
*/
int MatchCaptureBuffer.has(MatchCaptureBuffer *m, int index) {
  if (!m || index < 0 || index >= m.capacity || index >= MACHINE_BINDER_MAX)
    return 0;
  return _capture_bit(m.present, index);
}

static int _capture_bit(unsigned long bits, int index) =>
  (int) ((bits >> index) & 1UL);

/* lowering to Match words

   One recursive pass compiles a normalized pattern to machine words.
   Ordinary elements fuse against the segment cursor, star-free plain
   sublists descend inline through spare registers, and guards, quoted
   forms, and starred or deep sublists keep call frames. Stars, ordered
   alternatives, and negation are branch and call templates over generic
   words; there is no STAR, OR, or NOT instruction. */

#define MATCH_SEGMENT_MAX 128
#define MATCH_INLINE_MAX   64

/* The builder, the failure sites the enclosing block has yet to patch, and
   the call-frame depth of the block under construction. */
typedef struct MatchLower {
  MachineBuilder b;
  int *sites, site_count, site_capacity, depth;
} *MatchLower;

/** Compiles `pattern` into a reusable immutable `MatchPlan`.
    The caller owns the returned plan in the active `Scope`. Preparation
    records `MACHINE_PREPARED`, `MACHINE_MALFORMED`, or `MACHINE_INELIGIBLE`
    in the plan and raises for none of them; only a prepared plan has a
    program. `reason` is a borrowed static category string. The plan borrows
    pattern constants, which must outlive it.
    Raises: `<alloc-fail>` while analyzing, lowering, or freezing.
*/
MatchPlan MatchPlan.prepare(Var pattern) {
  MatchPlan plan = Scope.malloc(sizeof(struct MatchPlan));
  plan.program = NULL;
  plan.layout = MatchCaptureLayout.analyze(pattern);
  plan.status = plan.layout.status;
  plan.reason = plan.layout.reason;
  if (plan.status == MACHINE_PREPARED) plan._lower(plan.layout.normalized);
  return plan;
}

/* Lowers the normalized pattern and freezes an exact-sized program in the
   caller's scope. The builder interns the layout's binders first, so its
   slots are the layout's. */
static void MatchPlan._lower(MatchPlan plan, Var pattern) {
  MachineBuilder b = MachineBuilder.new();
  struct MatchLower storage = {.b = b, .depth = 1};
  MatchLower l = &storage;
  for (int i = 0; i < plan.layout.binder_count; i++)
    if (b.binder(plan.layout.binders[i]) != i) break;
  b.root = b.status == MACHINE_PREPARED ? l._compile_value(pattern) : -1;
  if (b.root < 0) l._fail("lowering");
  plan.status = b.status;
  plan.reason = b.reason;
  if (plan.status == MACHINE_PREPARED) plan.program = b.freeze();
  if (l.sites) Scope.free(l.sites);
  b.free();
}

/** Releases resources owned by `plan`.
    A null plan is ignored; the plan, layout, program, and all aliases to them
    are invalid afterward. Borrowed pattern constants are not released.
*/
void MatchPlan.free(MatchPlan plan) {
  if (!plan) return;
  MachineProgram.free(plan.program);
  MatchCaptureLayout.free(plan.layout);
  Scope.free(plan);
}

/* Compiles one pattern into a block and returns its entry, or -1. */
static int MatchLower._compile_value(MatchLower l, Var pattern) {
  if (pattern.is_atom_binder()) return l._compile_binder(pattern);
  if (pattern is not <list>) return l._compile_literal(pattern);
  List list = pattern;
  if (list && list.car().is_match_op())
    return l._compile_guard(list.car(), list.cdr());
  if (list && _is_list_literal(list)) return l._compile_literal_list(list);
  return l._compile_segment(list);
}

static int MatchLower._compile_binder(MatchLower l, Var binder) {
  int entry = l.b.length;
  if (binder == <?>) {
    l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
    return l._stopped() ? -1 : entry;
  }
  int base = l.site_count;
  if (!l._emit_binder(binder)) return -1;
  return l._finish(base) ? entry : -1;
}

/* Binds a fresh slot to the current value, or compares a bound one. */
static int MatchLower._emit_binder(MatchLower l, Var binder) {
  if (binder == <?>) return 1;
  MachineBuilder b = l.b;
  int slot = b.binder(binder);
  if (slot < 0) return 0;
  int valid = b.emit(MW_SLOT_VALID, slot, 0, 0, 0, -1);
  b.emit(MW_SLOT_SET_VALUE, slot, 0, 0, 0, 0);
  int done = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  if (valid < 0 || done < 0) return 0;
  int compare = b.length;
  if (!l._fail_site(MW_SLOT_EQ_VALUE, slot, 0, 0, 0)) return 0;
  b.set_target(valid, compare);
  b.set_target(done, b.length);
  return 1;
}

static int MatchLower._compile_literal(MatchLower l, Var pattern) {
  MachineBuilder b = l.b;
  int constant = b.constant(pattern);
  if (constant < 0) return -1;
  int mode = _compare_mode(pattern), entry = b.length;
  int miss = b.emit(MW_EQ_VALUE_CONST, constant, 0, 0, mode, -1);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  int failure = b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  if (failure < 0) return -1;
  b.set_target(miss, failure);
  return entry;
}

/* The comparison a word applies to the constant `value`. */
static int _compare_mode(Var value) =>
  _bits_unique(value) ? MACHINE_COMPARE_BITS : MACHINE_COMPARE_EQUAL;

/* Raw-bit comparison may replace general Var equality only where the two
   agree: Symbols are canonical identities and narrow integer immediates are
   value-encoded per family and width. Wide boxes carry value semantics
   across distinct allocations, floating NaN is unequal to itself with equal
   bits, and a transient mutable String can be content-equal to a canonical
   String with different bits. Interning gives two Lists one identity
   exactly when their elements are bit-equal, so a List answers for its
   elements. */
static int _bits_unique(Var value) {
  switch (value.tag()) {
    case <symbol>: case <lsym>:
    case <i8>: case <u8>: case <i16>: case <u16>:
    case <i32>: case <u32>: case <i48>: case <u48>:
      return 1;
    case <list>: {
      foreach (Var part, (List) value.pointer())
        if (!_bits_unique(part)) return 0;
      return 1;
    }
  }
  return 0;
}

/* Inline test of the current value for an atom pattern inside a guard or
   segment template: literals compare, atom binders bind or compare through
   the journal in slot order, and the anonymous ? matches without emitting a
   word. Failure sites are recorded for the enclosing block to patch. */
static int MatchLower._emit_leaf_value(MatchLower l, Var pattern) {
  if (pattern.is_atom_binder()) return l._emit_binder(pattern);
  int constant = l.b.constant(pattern);
  if (constant < 0) return 0;
  int mode = _compare_mode(pattern);
  return l._fail_site(MW_EQ_VALUE_CONST, constant, 0, 0, mode);
}

/* A List with no binder and no guard at any depth. */
static int _is_list_literal(List pat) {
  if (!pat) return 1;
  Var head = pat.car();
  if (head.is_binder() || head.is_match_op()) return 0;
  if (head is not <list>) return _is_list_literal(pat.cdr());
  return _is_list_literal(head) && _is_list_literal(pat.cdr());
}

/* A binder-free literal list compares by canonical identity first and falls
   back to the elementwise segment, mirroring the recursive matcher's
   interned-list fast path without collapsing boxed-equal elements into a
   bit comparison. */
static int MatchLower._compile_literal_list(MatchLower l, List pattern) {
  MachineBuilder b = l.b;
  int constant = b.constant(pattern);
  if (constant < 0) return -1;
  int entry = b.length, miss = b.emit(MW_EQ_VALUE_BITS, constant, 0, 0, 0, -1);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  int segment = l._compile_segment(pattern);
  if (segment < 0) return -1;
  b.set_target(miss, segment);
  return entry;
}

/* blocks and failure sites

   A block returns success or failure to its caller. Each test that can fail
   records its branch on a shared site stack, and the block patches every
   site recorded since its `base` once it places its failure word. The
   builder keeps its first failure, so every later emission fails too. */

/* Frame-depth fence: a block compiled here executes through one more call
   frame than its parent, so programs that could exceed the machine's frame
   capacity are rejected at preparation instead of erroring mid-execution. */
static int MatchLower._compile_child(MatchLower l, Var pattern) {
  if (l.depth + 1 >= MACHINE_FRAME_MAX - 1) return l._fail("frame-depth");
  l.depth++;
  int entry = l._compile_value(pattern);
  l.depth--;
  return entry;
}

/* Emits the branch word with an unresolved target and records its patch
   site on the shared site stack. This is the only place a failure site is
   created. Every lowering path stops immediately on emission failure. */
static int MatchLower._fail_site(
  MatchLower l, int op, int a, int b, int c, int d) {
  int site = l.b.emit(op, a, b, c, d, -1);
  if (site < 0) return 0;
  if (l.site_count >= l.site_capacity) {
    int capacity = l.site_capacity ? l.site_capacity * 2 : 64;
    l.sites = Scope.realloc(l.sites, sizeof(int) * capacity);
    l.site_capacity = capacity;
  }
  l.sites[l.site_count++] = site;
  return 1;
}

/* Patches every site recorded since `base` to `target` and releases them.
   Block compilers leave the site stack at their entry base. */
static void MatchLower._patch_sites(MatchLower l, int base, int target) {
  for (int i = base; i < l.site_count; i++) l.b.set_target(l.sites[i], target);
  l.site_count = base;
}

static int MatchLower._finish(MatchLower l, int base) {
  l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  return l._finish_failure(base);
}

static int MatchLower._finish_failure(MatchLower l, int base) {
  int failure = l.b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  if (failure < 0) return 0;
  l._patch_sites(base, failure);
  return 1;
}

static int MatchLower._emit_call(MatchLower l, int child, int mode, int reg) {
  if (l.b.emit(MW_CALL, child, mode, reg, 0, 0) < 0) return 0;
  return l._fail_site(MW_BR_FAIL, 0, 0, 0, 0);
}

/* Records the first ineligibility reason and returns the failed entry. */
static int MatchLower._fail(MatchLower l, const char *reason) {
  MachineBuilder b = l.b;
  if (b.status == MACHINE_PREPARED) {
    b.status = MACHINE_INELIGIBLE;
    b.reason = reason;
  }
  return -1;
}

static int MatchLower._stopped(MatchLower l) => l.b.status != MACHINE_PREPARED;

/* guards

   A guard's operands compile first. An atom operand tests the current value
   inline; any other operand is a child block the guard calls on the current
   value. */

/* The operands of one guard, or the fixed prefix of one segment, with each
   element's entry: -1 for an atom tested inline, -2 for a sublist that
   descends inline, or else the entry of its child block. */
typedef struct MatchParts {
  Var elements[MATCH_SEGMENT_MAX];
  int entries[MATCH_SEGMENT_MAX], count;
} MatchParts;

static int MatchLower._compile_guard(MatchLower l, Var op, List args) {
  if (op == <!or>) return l._compile_or(args);
  if (op == <!not>) return l._compile_not(args);
  if (op == <!is>) return l._compile_is(args);
  if (op == <!set>) return l._compile_set(args);
  if (op == <!and>) return l._compile_and(args);
  return l._compile_quote(args);
}

/* Compiles each operand that is not an atom as a child block. */
static int MatchLower._guard_parts(
  MatchLower l, List args, MatchParts &parts) {
  int n = 0;
  foreach (Var part, args) {
    if (n >= MATCH_SEGMENT_MAX) return l._fail("guard-width") + 1;
    parts.elements[n] = part;
    if (part is not <list>) parts.entries[n++] = -1;
    else {
      parts.entries[n] = l._compile_child(part);
      if (parts.entries[n++] < 0) return 0;
    }
  }
  parts.count = n;
  return 1;
}

/* Tests operand `i` on the current value, inline for an atom. */
static int MatchLower._emit_operand(MatchLower l, MatchParts &parts, int i) {
  if (parts.entries[i] < 0) return l._emit_leaf_value(parts.elements[i]);
  return l._emit_call(parts.entries[i], MACHINE_CALL_CURRENT, 0);
}

/* Ordered alternatives are static call, branch, and return templates: every
   failed arm returns through its paired undo and order call-entry mark, and
   the first successful arm returns immediately as the local cut. */
static int MatchLower._compile_or(MatchLower l, List args) {
  MachineBuilder b = l.b;
  MatchParts operands;
  if (!l._guard_parts(args, operands)) return -1;
  int entry = b.length, base = l.site_count;
  for (int i = 0; i < operands.count; i++) {
    l._patch_sites(base, b.length);
    if (!l._emit_operand(operands, i)) return -1;
    if (b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0) < 0) return -1;
  }
  int failure = b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  if (failure < 0) return -1;
  l._patch_sites(base, failure);
  return entry;
}

/* Negation uses one frame-local mark and rolls the journal back on both
   inverted outcomes, so no child binding can leak. */
static int MatchLower._compile_not(MatchLower l, List args) {
  MachineBuilder b = l.b;
  MatchParts operands;
  if (!l._guard_parts(args, operands)) return -1;
  int entry = b.length, base = l.site_count;
  b.emit(MW_MARK, 0, 0, 0, 0, 0);
  int successes[MATCH_SEGMENT_MAX];
  for (int i = 0; i < operands.count; i++) {
    l._patch_sites(base, b.length);
    if (!l._emit_operand(operands, i)) return -1;
    successes[i] = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
    if (successes[i] < 0) return -1;
  }
  int all_failed = b.length;
  l._patch_sites(base, all_failed);
  b.emit(MW_ROLLBACK, 0, MACHINE_ROLLBACK_RESTORE, 0, 0, 0);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  int rejected = b.length;
  b.patch(successes, operands.count, rejected);
  b.emit(MW_ROLLBACK, 0, MACHINE_ROLLBACK_RESTORE, 0, 0, 0);
  if (b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0) < 0) return -1;
  return entry;
}

/* `(!set BINDER TEST)` binds and tests in one block; any other set is a
   list of ordered alternatives. */
static int MatchLower._compile_set(MatchLower l, List args) {
  if (!args || !args.cdr() || args.cddr() || !args.car().is_atom_binder())
    return l._compile_or(args);
  Var (binder, test) = args;
  if (test is not <list>) return l._compile_bind_and_leaf(binder, test);
  int child = l._compile_child(test);
  if (child < 0) return -1;
  return l._compile_bind_and(binder, child);
}

static int MatchLower._compile_bind_and(MatchLower l, Var binder, int child) {
  MachineBuilder b = l.b;
  int entry = b.length, base = l.site_count;
  if (!l._emit_binder(binder) || !l._emit_call(child, MACHINE_CALL_CURRENT, 0))
    return -1;
  return l._finish(base) ? entry : -1;
}

/* Bind-and-test whose test is an atom pattern needs no call frame:
   the binder triple and the inline leaf test share one block. */
static int MatchLower._compile_bind_and_leaf(
  MatchLower l, Var binder, Var leaf) {
  MachineBuilder b = l.b;
  int entry = b.length, base = l.site_count;
  if (!l._emit_binder(binder) || !l._emit_leaf_value(leaf)) return -1;
  return l._finish(base) ? entry : -1;
}

/* Every operand must match the current value, in order. */
static int MatchLower._compile_and(MatchLower l, List args) {
  MatchParts operands;
  if (!l._guard_parts(args, operands)) return -1;
  int entry = l.b.length, base = l.site_count;
  for (int i = 0; i < operands.count; i++)
    if (!l._emit_operand(operands, i)) return -1;
  return l._finish(base) ? entry : -1;
}

/* The runtime compares only one quoted operand. */
static int MatchLower._compile_quote(MatchLower l, List args) {
  if (!args || args.cdr()) return l._fail("quote-arity");
  return l._compile_literal(args.car());
}

/* type tests

   `!is` tests the current value against a fixed vocabulary: its binder or
   operator kind, whether it is an atom, or its tag. An unknown shape fails
   at execution. */

static int MatchLower._compile_is(MatchLower l, List args) {
  int kind = _match_kind(args);
  if (kind >= 0) return l._is_kind(kind);
  if (args == %(atom)) return l._is_atom();
  if (args && args.car() == <type> && args.cdr() && !args.cddr())
    return l._is_type(args.cadr());
  return l._never();
}

/* The binder or operator test an `!is` shape names, or -1. */
static int _match_kind(List args) {
  if (args == %(var binder)) return MACHINE_KIND_ATOM_BINDER;
  if (args == %(list binder)) return MACHINE_KIND_LIST_BINDER;
  if (args == %(binder)) return MACHINE_KIND_BINDER;
  if (args == %(op)) return MACHINE_KIND_MATCH_OP;
  return -1;
}

static int MatchLower._is_kind(MatchLower l, int kind) {
  int entry = l.b.length, base = l.site_count;
  if (!l._fail_site(MW_MATCH_KIND, 0, kind, 0, 0)) return -1;
  return l._finish(base) ? entry : -1;
}

/* `(atom)` holds for any value whose tag is not `list`. */
static int MatchLower._is_atom(MatchLower l) {
  MachineBuilder b = l.b;
  int entry = b.length, constant = b.constant(<list>);
  if (constant < 0) return -1;
  int hit = b.emit(MW_TAG, constant, 0, 0, 0, -1);
  int is_list = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  if (hit < 0 || is_list < 0) return -1;
  int success = b.length;
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  int failure = b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  if (failure < 0) return -1;
  b.set_target(hit, success);
  b.set_target(is_list, failure);
  return entry;
}

/* `(type TAG)` canonicalizes varray and vmap to the public tags before
   freezing the constant; a TAG that is not a Symbol never matches. */
static int MatchLower._is_type(MatchLower l, Var type) {
  Symbol tag = _canonical_type_tag(type is <symbol> ? type.symbol() : 0);
  if (!tag) return l._never();
  int entry = l.b.length, base = l.site_count, constant = l.b.constant(tag);
  if (constant < 0 || !l._fail_site(MW_TAG, constant, 0, 0, 0)) return -1;
  return l._finish(base) ? entry : -1;
}

static inline Symbol _canonical_type_tag(Symbol tag) {
  if (tag == <varray>) return <array>;
  if (tag == <vmap>)   return <map>;
  return tag;
}

/* A block that always fails. */
static int MatchLower._never(MatchLower l) {
  int entry = l.b.length;
  return l.b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0) < 0 ? -1 : entry;
}

/* segments

   A segment matches a List element by element: a fixed prefix, then at
   most one star and the tail after it. Every child block compiles before
   the segment's own words, so the segment emits in one linear pass. */

/* Child blocks framed inside inline sublists, compiled in traversal order
   so that emission consumes them in the same order. */
typedef struct MatchInlinePlan {
  int entries[MATCH_INLINE_MAX], count, used;
} MatchInlinePlan;

/* The star that ends a segment's prefix, at `cell`, and the `tail` after
   it. The binder has `slot`, or -1 for `*`; a `delayed` binder takes its
   span only once the tail succeeds. The tail is the child block at `entry`,
   and `anchor` is its first element that a scan can compare as one value,
   `offset` elements in. */
typedef struct MatchStar {
  List cell, tail;
  int slot, delayed, entry, anchored, offset;
  Var anchor;
} MatchStar;

/* One segment under lowering: its prefix, the framed children nested in
   its inline sublists, and its star. */
typedef struct MatchSegment {
  MatchParts prefix;
  MatchInlinePlan nested;
  MatchStar star;
} MatchSegment;

static int MatchLower._compile_segment(MatchLower l, List pattern) {
  MatchSegment s;
  s.nested.count = 0;
  s.nested.used = 0;
  if (!l._segment_prefix(s, pattern) || !l._segment_star(s.star)) return -1;
  int entry = l.b.length, base = l.site_count;
  if (!l._fail_site(MW_INPUT_LIST, 0, 0, 0, 0) || !l._emit_prefix(s) ||
      !l._segment_end(s.star))
    return -1;
  return l._finish_failure(base) ? entry : -1;
}

/* Compiles the children of the prefix, which runs up to the first star.
   An atom executes inline against the cursor head; a star-free plain
   sublist descends inline through the next register; guards, quoted forms,
   literal lists, and starred or deep sublists keep a call frame with an
   independent register bank. */
static int MatchLower._segment_prefix(
  MatchLower l, MatchSegment &s, List pattern) {
  MatchParts *prefix = &s.prefix;
  int n = 0, List at = pattern;
  while (at && !at.car().is_list_binder()) {
    if (n >= MATCH_SEGMENT_MAX) return l._fail("segment-width") + 1;
    Var part = at.car();
    prefix.elements[n] = part;
    if (part is not <list>) prefix.entries[n++] = -1;
    else if (_inline_descend_ok(part, 0)) {
      if (!l._compile_nested(part, 1, s.nested)) return 0;
      prefix.entries[n++] = -2;
    }
    else {
      prefix.entries[n] = l._compile_child(part);
      if (prefix.entries[n++] < 0) return 0;
    }
    at = at.cdr();
  }
  prefix.count = n;
  s.star.cell = at;
  return 1;
}

/* A star-free plain nested segment may execute in the enclosing frame
   through the bank's next cursor register: stars are the only other
   consumers of registers one and two and always run in their own frame;
   guards and quoted forms keep call frames, and literal lists keep the
   canonical-identity path. */
static int _inline_descend_ok(List child, int reg) {
  if (reg + 1 >= MACHINE_CURSOR_REGS) return 0;
  if (!child) return 0;
  if (child.car().is_match_op()) return 0;
  if (_is_list_literal(child)) return 0;
  foreach (Var part, child) if (part.is_list_binder()) return 0;
  return 1;
}

/* Precompiles every framed child block reachable through inline descents,
   in traversal order. */
static int MatchLower._compile_nested(
  MatchLower l, List pattern, int reg, MatchInlinePlan &nested) {
  foreach (Var part, pattern) {
    if (part is not <list>) continue;
    List child = part;
    if (_inline_descend_ok(child, reg)) {
      if (!l._compile_nested(child, reg + 1, nested)) return 0;
      continue;
    }
    if (nested.count >= MATCH_INLINE_MAX) return l._fail("segment-width") + 1;
    nested.entries[nested.count] = l._compile_child(part);
    if (nested.entries[nested.count++] < 0) return 0;
  }
  return 1;
}

/* Resolves the star after the prefix: its binder's slot, whether the
   binder can defer its span, and the tail with its anchor. A binder the
   tail never mentions is delayed until the tail succeeds. */
static int MatchLower._segment_star(MatchLower l, MatchStar &star) {
  List cell = star.cell;
  star = (MatchStar) {.cell = cell, .slot = -1, .entry = -1, .anchor = void};
  if (!cell) return 1;
  Var binder = cell.car();
  star.tail = cell.cdr();
  if (binder != <*>) {
    star.slot = l.b.binder(binder);
    if (star.slot < 0) return 0;
    star.delayed = star.tail && !_pattern_contains_binder(star.tail, binder);
  }
  if (!star.tail) return 1;
  star.entry = l._compile_tail(star.tail);
  if (star.entry < 0) return 0;
  star.anchored = _find_fixed_anchor(star.tail, star.anchor, star.offset);
  return 1;
}

static int _pattern_contains_binder(List pat, Var binder) {
  foreach (Var part, pat) {
    if (part == binder) return 1;
    if (part is <list>) {
      List nested = part;
      if (nested && nested.car() != <!quote> &&
          _pattern_contains_binder(nested, binder))
        return 1;
    }
  }
  return 0;
}

/* A star's tail compiles as a child segment under the frame-depth fence. */
static int MatchLower._compile_tail(MatchLower l, List pattern) {
  if (l.depth + 1 >= MACHINE_FRAME_MAX - 1) return l._fail("frame-depth");
  l.depth++;
  int entry = l._compile_segment(pattern);
  l.depth--;
  return entry;
}

/* An anchor is compared as one value, so a List qualifies only when its
   bits decide it. Otherwise the scan would reject an input sublist that
   the same pattern matches element by element at a fixed position. */
static int _find_fixed_anchor(List pat, Var &anchor, int &offset) {
  int width = 0;
  foreach (Var part, pat) {
    if (part.is_list_binder()) return 0;
    if ((part is not <list> && !part.is_binder()) ||
        (part is <list> && _is_list_literal(part) && _bits_unique(part))) {
      anchor = part;
      offset = width;
      return 1;
    }
    width++;
  }
  return 0;
}

/* prefix emission

   An atom tests the cursor head, an inline sublist descends through the
   next register, and any other element is a child block called on the
   head. Each element then advances the cursor. */

static int MatchLower._emit_prefix(MatchLower l, MatchSegment &s) {
  for (int i = 0; i < s.prefix.count; i++) if (!l._emit_part(s, i)) return 0;
  return 1;
}

/* An atom tests the cursor head, an inline sublist descends through
   register 1, and a child block is called on the head. */
static int MatchLower._emit_part(MatchLower l, MatchSegment &s, int i) {
  int entry = s.prefix.entries[i];
  if (entry == -1) return l._emit_head_leaf(s.prefix.elements[i], 0);
  if (entry == -2) return l._emit_descend(s.prefix.elements[i], 0, s.nested);
  return l._emit_framed(entry, 0);
}

/* Tests the element at the cursor head of `reg`: `?` skips it, an atom
   binder binds or compares it, and a literal compares it. */
static int MatchLower._emit_head_leaf(MatchLower l, Var part, int reg) {
  MachineBuilder b = l.b;
  if (part == <?>) return l._fail_site(MW_SKIP_HEAD, 0, reg, 0, 0);
  if (part.is_atom_binder()) {
    int slot = b.binder(part);
    if (slot < 0) return 0;
    return l._fail_site(MW_BIND_HEAD, slot, reg, 0, 0);
  }
  int constant = b.constant(part);
  if (constant < 0) return 0;
  int mode = _compare_mode(part);
  return l._fail_site(MW_EQ_HEAD_CONST, constant, reg, 0, mode);
}

/* Descends into the sublist at the cursor head of `reg` through the next
   register, then advances past it. */
static int MatchLower._emit_descend(
  MatchLower l, List child, int reg, MatchInlinePlan &nested) =>
  l._fail_site(MW_DESCEND, 0, reg, reg + 1, 0) &&
  l._emit_inline_segment(child, reg + 1, nested) &&
  l.b.emit(MW_ADVANCE, reg, 0, 0, 0, 0) >= 0;

/* Calls a child block on the cursor head of `reg`, which must exist, then
   advances past it. */
static int MatchLower._emit_framed(MatchLower l, int entry, int reg) =>
  l._fail_site(MW_NONNIL, reg, 0, 0, 0) &&
  l._emit_call(entry, MACHINE_CALL_HEAD, reg) &&
  l.b.emit(MW_ADVANCE, reg, 0, 0, 0, 0) >= 0;

/* Emits an inline sublist through `reg`; its elements must end with it. */
static int MatchLower._emit_inline_segment(
  MatchLower l, List pattern, int reg, MatchInlinePlan &nested) {
  foreach (Var part, pattern) {
    if (part is not <list>) {
      if (!l._emit_head_leaf(part, reg)) return 0;
      continue;
    }
    List child = part;
    if (_inline_descend_ok(child, reg)) {
      if (!l._emit_descend(child, reg, nested)) return 0;
      continue;
    }
    assert(nested.used < nested.count);
    if (!l._emit_framed(nested.entries[nested.used++], reg)) return 0;
  }
  return l._fail_site(MW_NIL, reg, 0, 0, 0);
}

/* stars

   A segment without a star ends at nil. A final star takes the rest of the
   List; an interior star searches the List for a split where the tail
   matches. */

static int MatchLower._segment_end(MatchLower l, MatchStar &star) {
  if (!star.cell) {
    if (!l._fail_site(MW_NIL, 0, 0, 0, 0)) return 0;
    l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
    return 1;
  }
  if (!star.tail) return l._final_star(star.slot);
  return l._search_star(star);
}

/* A final star consumes the remaining input: a fresh binder shares the
   native suffix directly, and a repeated binder keeps production's shallow
   List identity rule and memoizes a proven span as its suffix VALUE. */
static int MatchLower._final_star(MatchLower l, int slot) {
  MachineBuilder b = l.b;
  if (slot < 0) return b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0) >= 0;

  int valid = b.emit(MW_SLOT_VALID, slot, 0, 0, 0, -1);
  b.emit(MW_CURSOR_VALUE, 0, 1, 0, 0, 0);
  b.emit(MW_SLOT_SET_VALUE, slot, 0, 0, 0, 0);
  int fresh = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  if (valid < 0 || fresh < 0) return 0;

  int existing = b.length;
  int is_span = b.emit(MW_SLOT_IS_SPAN, slot, 0, 0, 0, -1);
  b.emit(MW_CURSOR_VALUE, 0, 0, 0, 0, 0);
  if (!l._fail_site(MW_SLOT_EQ_VALUE, slot, 0, 0, 0)) return 0;
  int value_done = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  if (is_span < 0 || value_done < 0) return 0;

  int compare_span = b.length;
  if (!l._fail_site(MW_SLOT_EQ_FINAL_IDENTITY, slot, 0, 1, 0)) return 0;
  b.emit(MW_CURSOR_VALUE, 0, 1, 0, 0, 0);
  b.emit(MW_SLOT_SET_VALUE, slot, 1, 0, 0, 0);

  int success = b.length;
  if (b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0) < 0) return 0;
  b.set_target(valid, existing);
  b.set_target(is_span, compare_span);
  b.set_target(fresh, success);
  b.set_target(value_done, success);
  return 1;
}

/* An interior star enumerates shortest-first splits. An anchored star pairs
   monotonic split and probe cursors through one fused SCAN; an unanchored
   star advances one optional split per retry. A unique unreferenced binder
   defers its span until the tail succeeds, and a repeated binder compares
   the candidate range in place. */
static int MatchLower._search_star(MatchLower l, MatchStar &star) {
  MachineBuilder b = l.b;
  int slot = star.slot, loop = l._star_loop(star);
  if (loop < 0) return 0;
  int valid = -1;
  if (slot >= 0) valid = b.emit(MW_SLOT_VALID, slot, 0, 0, 0, -1);
  int fresh_failed = l._star_fresh(star);
  if (fresh_failed < 0) return 0;

  int mismatch = -1, existing_failed = -1;
  if (slot >= 0) {
    int compare = b.length;
    mismatch = b.emit(MW_SLOT_EQ_PREFIX, slot, 0, 1, 0, -1);
    existing_failed = l._star_tail(star);
    if (mismatch < 0 || existing_failed < 0) return 0;
    b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
    b.set_target(valid, compare);
  }

  int retry = b.length;
  b.set_target(mismatch, retry);
  b.set_target(fresh_failed, retry);
  b.set_target(existing_failed, retry);
  return l._star_retry(star, loop);
}

/* Starts the split cursors and emits the loop head, which fails the
   segment once no split remains. Returns the head's site, or -1. */
static int MatchLower._star_loop(MatchLower l, MatchStar &star) {
  MachineBuilder b = l.b;
  int anchored = star.anchored;
  int constant = anchored ? b.constant(star.anchor) : -1;
  if (anchored && constant < 0) return -1;
  int mode = anchored ? _compare_mode(star.anchor) : MACHINE_COMPARE_BITS;
  b.emit(MW_MARK, 0, 0, 0, 0, 0);
  b.emit(MW_MOVE, 1, 0, 0, 0, 0);
  if (anchored) {
    b.emit(MW_MOVE, 2, 1, 0, 0, 0);
    b.emit(MW_OFFSET, 2, star.offset, 0, 0, 0);
  }
  else
    b.emit(MW_SET_ACTIVE, 0, 1, 0, 0, 0);

  int loop = b.length;
  int emitted = anchored
    ? l._fail_site(MW_SCAN, 1, 2, constant, mode)
    : l._fail_site(MW_REQUIRE_ACTIVE, 0, 0, 0, 0);
  return emitted ? loop : -1;
}

/* A fresh binder takes the split's span before the tail runs or, when
   delayed, after it succeeds. Returns the tail's failure branch, or -1. */
static int MatchLower._star_fresh(MatchLower l, MatchStar &star) {
  MachineBuilder b = l.b;
  int slot = star.slot;
  if (slot >= 0 && !star.delayed) b.emit(MW_SLOT_SET_SPAN, slot, 0, 1, 0, 0);
  int failed = l._star_tail(star);
  if (failed < 0) return -1;
  if (slot >= 0 && star.delayed) b.emit(MW_SLOT_SET_SPAN, slot, 0, 1, 0, 0);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  return failed;
}

/* Calls the tail at the split cursor; returns its failure branch. */
static int MatchLower._star_tail(MatchLower l, MatchStar &star) {
  l.b.emit(MW_CALL, star.entry, MACHINE_CALL_CURSOR, 1, 0, 0);
  return l.b.emit(MW_BR_FAIL, 0, 0, 0, 0, -1);
}

/* Undoes the failed split's bindings and moves to the next split. */
static int MatchLower._star_retry(MatchLower l, MatchStar &star, int loop) {
  MachineBuilder b = l.b;
  b.emit(MW_ROLLBACK, 0, MACHINE_ROLLBACK_RETRY, 0, 0, 0);
  if (star.anchored) {
    b.emit(MW_ADVANCE, 1, 0, 0, 0, 0);
    b.emit(MW_ADVANCE, 2, 0, 0, 0, 0);
  }
  else
    b.emit(MW_ADVANCE_OPTIONAL, 1, 0, 0, 0, 0);
  return b.emit(MW_JUMP, 0, 0, 0, 0, loop) >= 0 && !l._stopped();
}

/* plan execution

   Only a prepared plan runs. An entry point raises the fence of an
   ineligible plan, and a malformed plan answers no match. */

/* The one place an ineligible pattern is reported. Such a pattern compiles
   to no program, so answering "no match" would be wrong and no caller could
   tell it from a real miss. Every entry point raises here instead, naming
   the fence the pattern crossed. */
static void _raise_ineligible(const char *reason, const char *owner) {
  String fence = String.new(reason), site = String.new(owner);
  raise %(size-limit (owner $site) (fence $fence));
}

/* Entry-point guard over an already prepared plan; `plan` stays owned by
   its caller. Malformed patterns keep their categorized no-match. */
static int _plan_prepared(MatchPlan plan, const char *owner) {
  if (plan && plan.status == MACHINE_INELIGIBLE)
    _raise_ineligible(plan.reason, owner);
  return plan && plan.status == MACHINE_PREPARED;
}

static int _capture_buffer_valid(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures) {
  if (!layout || !captures) return 0;
  if (captures.capacity < layout.binder_count) return 0;
  return !layout.binder_count || captures.values != NULL;
}

/* Declares `$instance`, an open machine in stack storage. */
macro Statement $match.machine(Name $instance, Expr $stats) {
  struct MatchMachine storage;
  MatchMachine $instance = &storage;
  $instance.open();
  $instance.stats = $stats;
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
  if (!_plan_prepared(m, "MatchPlan.execute_capture") ||
      !_capture_buffer_valid(m.layout, captures))
    return -1;
  return m._capture(input, captures, stats);
}

/** Executes a prepared `List` match into caller-owned positional storage.
    This is `MatchPlan.execute_capture` without statistics and has the same
    results, atomicity, and failures.
*/
int MatchPlan.try_capture(
  MatchPlan plan, List input, MatchCaptureBuffer &?captures) =>
    plan.execute_capture(input, captures, NULL);

static int MatchPlan._capture(
  MatchPlan m, Var input, MatchCaptureBuffer *captures, MachineStats *stats) {
  $match.machine(machine, stats);
  int result = _run_capture(m.program.view(), machine, input, captures);
  machine.dispose();
  return result;
}

/* Runs one prepared execution and commits positional values only after the
   machine and every lazy-span materialization have succeeded. */
static int _run_capture(
  MachineView view, MatchMachine m, Var input, MatchCaptureBuffer *captures) {
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
  MachineView view, MatchMachine m, MatchCaptureBuffer *captures) {
  Var values[MACHINE_BINDER_MAX];
  unsigned long present = 0;
  for (int i = 0; i < view.binder_count; i++) {
    MachineSlot *slot = &m.slots[i];
    if (slot.kind == MACHINE_SLOT_INVALID) continue;
    values[i] = slot.value;
    if (slot.kind == MACHINE_SLOT_SPAN)
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
  if (!_plan_prepared(plan, "MatchPlan.execute")) return -1;
  if (!out_bindings) return -1;
  $match.machine(machine, stats);
  List bindings, int result = plan._run(machine, input, bindings);
  machine.dispose();
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
static int MatchPlan._run(MatchPlan mm, MatchMachine m, Var input, List &out) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = { values, 0, MACHINE_BINDER_MAX };
  int result = _run_capture(mm.program.view(), m, input, &captures);
  if (result == 1) out = _capture_publish(mm.layout, &captures);
  return result;
}

/* The committed captures as an association List in reverse slot order. */
static List _capture_publish(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures) {
  List bindings = NULL;
  for (int i = 0; i < layout.binder_count; i++) {
    if (!_capture_bit(captures.present, i)) continue;
    List pair = %(${layout.binders[i]} ${captures.values[i]});
    bindings = cons(pair, bindings);
  }
  return bindings;
}

/* searches

   A search visits a List's head, then its tail, then the List itself. An
   explicit `nil` element is a node, but a proper List's terminal cdr is
   traversal structure and is never tested. */

/* One prepared walk owns a layout, machine, capture buffer, and the cell
   stack its cdr loops share. Each level takes the region above the length
   it found and restores that length before returning, so one growing
   allocation serves the whole traversal. The first-match walk writes
   `found` and `bindings`, the search walk `results`, and the replacing walk
   reads `template` and sets `error`. */
typedef struct MatchWalk {
  MatchPlan plan;
  MachineView view;
  MatchCaptureBuffer *captures;
  MatchMachine m;
  Block spine;
  Var found, template;
  List bindings, results;
  int error;
} *MatchWalk;

/* Declares `$walk` over `$plan` and `$machine` with its own capture buffer
   and an empty cell stack. */
macro Statement $match.walk(Expr $plan, Expr $machine, Name $walk) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = { values, 0, MACHINE_BINDER_MAX };
  struct MatchWalk storage = {
    $plan, ($plan).program.view(), &captures, $machine,
    Block.new(sizeof(Var))
  };
  MatchWalk $walk = &storage;
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
  if (!_plan_prepared(plan, "MatchPlan.try_search") || !out_match ||
      !out_bindings)
    return -1;
  return plan._first(input, out_match, out_bindings);
}

static int MatchPlan._first(
  MatchPlan plan, List input, Var *out_match, List *out_bindings) {
  $match.machine(machine, NULL);
  $match.walk(plan, machine, walk);
  int result = walk._first(input, 1);
  walk.spine.free();
  machine.dispose();
  if (result == 1) {
    *out_match = walk.found;
    *out_bindings = walk.bindings;
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
  if (!_plan_prepared(plan, "MatchPlan.search") || !out_results) return -1;
  return plan._all(input, out_results);
}

static int MatchPlan._all(MatchPlan plan, List input, List &out_results) {
  $match.machine(machine, NULL);
  $match.walk(plan, machine, walk);
  int status = walk._all(input, 1);
  walk.spine.free();
  machine.dispose();
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
  if (!_plan_prepared(plan, "MatchPlan.search_replace") || !out) return -1;
  return plan._replace_all(input, template, out);
}

static int MatchPlan._replace_all(
  MatchPlan plan, List input, Var template, List *out) {
  $match.machine(machine, NULL);
  $match.walk(plan, machine, walk);
  walk.template = template;
  Var result = walk._rewrite(input, 1);
  walk.spine.free();
  machine.dispose();
  if (walk.error) return -1;
  *out = result;
  return 1;
}

/* walks

   A walk runs the plan at each node of one traversal, sharing one machine,
   one capture buffer, and one cell stack. */

static int MatchWalk._test(MatchWalk walk, Var node) =>
  _run_capture(walk.view, walk.m, node, walk.captures);

/* One search result: `(* node)` followed by the node's bindings. */
static List MatchWalk._hit(MatchWalk walk, Var node) =>
  cons(%(* $node), _capture_publish(walk.plan.layout, walk.captures));

static Var _spine_get(Block spine, size_t index) =>
  ((Var *) spine.bytes)[index];

/* Every traversal descends car with include_empty=1 and cdr with
   include_empty=0 before trying the match at this node. The cdr descent runs
   as a loop, so a `List` of any length costs one frame and only nesting
   depth reaches the C stack. The loop visits every car in order and then
   answers for the cells from the last one back, which is the order the
   recursion produced. */
static int MatchWalk._all(MatchWalk walk, Var input, int include_empty) {
  Block hits = walk.spine;
  size_t base = hits.length;
  int visit_tail = 1;
  while (input is <list>) {
    List lst = input;
    if (!lst) {
      visit_tail = include_empty;
      break;
    }
    if (walk._all(lst.car(), 1) < 0) return -1;
    int status = walk._test(input);
    if (status < 0) return -1;
    if (status == 1) {
      Var hit = walk._hit(input);
      hits.push(&hit);
    }
    input = lst.cdr();
    include_empty = 0;
  }
  if (visit_tail) {
    int status = walk._test(input);
    if (status < 0) return -1;
    if (status == 1) walk.results = cons(walk._hit(input), walk.results);
  }
  walk._answer(base);
  return 0;
}

/* Prepends the hits the loop pushed above `base`, last one first, as the
   recursion answered them, and releases them. */
static void MatchWalk._answer(MatchWalk walk, size_t base) {
  Block hits = walk.spine;
  for (size_t i = hits.length; i > base; i--)
    walk.results = cons(_spine_get(hits, i - 1), walk.results);
  hits.truncate(base);
}

/* The cells answer from the last one back, so the walk remembers the last
   cell that matched and settles on it once nothing earlier matches. */
static int MatchWalk._first(MatchWalk walk, Var input, int include_empty) {
  Var last_cell = void;
  int have_cell = 0, visit_tail = 1;
  while (input is <list>) {
    List lst = input;
    if (!lst) {
      visit_tail = include_empty;
      break;
    }
    int found = walk._first(lst.car(), 1);
    if (found) return found;
    int status = walk._test(input);
    if (status < 0) return -1;
    if (status == 1) {
      last_cell = input;
      have_cell = 1;
    }
    input = lst.cdr();
    include_empty = 0;
  }
  if (visit_tail) {
    int status = walk._settle(input);
    if (status) return status;
  }
  // the buffer now holds a later node, so the winner runs once more
  return have_cell ? walk._settle(last_cell) : 0;
}

/* Tests `node` and, when it matches, publishes it with its bindings. */
static int MatchWalk._settle(MatchWalk walk, Var node) {
  int status = walk._test(node);
  if (status != 1) return status;
  walk.found = node;
  walk.bindings = _capture_publish(walk.plan.layout, walk.captures);
  return 1;
}

/* Rewrites children before the List that holds them. The loop pushes each
   rewritten car; the cells then rebuild from the last one back, each around
   the tail so far. */
static Var MatchWalk._rewrite(MatchWalk walk, Var node, int include_empty) {
  Block heads = walk.spine;
  size_t base = heads.length;
  int visit_tail = 1;
  while (node is <list>) {
    List lst = node;
    if (!lst) {
      visit_tail = include_empty;
      break;
    }
    Var head = walk._rewrite(lst.car(), 1);
    if (walk.error) return node;
    heads.push(&head);
    node = lst.cdr();
    include_empty = 0;
  }
  if (visit_tail) node = walk._replace_node(node);
  for (size_t i = heads.length; i > base && !walk.error; i--) {
    List tail = node;
    node = walk._replace_node(cons(_spine_get(heads, i - 1), tail));
  }
  heads.truncate(base);
  return node;
}

/* The instantiated template when `node` matches, or else `node`. */
static Var MatchWalk._replace_node(MatchWalk walk, Var node) {
  int status = walk._test(node);
  if (status < 0) {
    walk.error = 1;
    return node;
  }
  if (status == 0) return node;
  return _capture_replace(walk.template, walk.plan.layout, walk.captures);
}

/* templates

   Instantiation replaces each named binder with its value. A sequence
   binder at a List's head splices its captured List; a binder the match
   left unbound is retained as one element, so no result is ever void.
   `!quote` yields its operand unchanged. */

/** Executes `plan` and writes the instantiated `template` on success.
    Returns 1 after writing any `Var` result, 0 on a miss, and -1 for an
    unusable plan, null output, or machine error. Non-success leaves `out`
    unchanged.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    materializing captures or replacing.
*/
int MatchPlan.try_match_replace(
  MatchPlan plan, List input, Var template, Var &?out) {
  if (!_plan_prepared(plan, "MatchPlan.try_match_replace") || !out) return -1;
  return plan._replace(input, template, out);
}

static int MatchPlan._replace(
  MatchPlan plan, List input, Var template, Var *out) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = { values, 0, MACHINE_BINDER_MAX };
  int result = plan._capture(input, &captures, NULL);
  if (result != 1) return result;
  *out = _capture_replace(template, plan.layout, &captures);
  return 1;
}

/* Instantiates `input` from committed captures. */
static Var _capture_replace(
  Var input, MatchCaptureLayout layout, MatchCaptureBuffer *captures) {
  if (_named_binder(input)) return _captured(layout, captures, input);
  if (input is not <list>) return input;
  List list = input;
  if (!list) return input;
  Var head = list.car();
  List tail = list.cdr();
  if (head == <!quote>) return tail.car();
  int splice = head.is_list_binder() && head != <*> && head != <?>;
  Var replaced_head = _capture_replace(head, layout, captures);
  List replaced_tail = _capture_replace(tail, layout, captures);
  if (splice && replaced_head is <list>) {
    List spliced = replaced_head;
    return %(@spliced @replaced_tail);
  }
  return %($replaced_head @replaced_tail);
}

/* The value captured for `binder`, or the binder when the match left it
   unbound. */
static Var _captured(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures, Var binder) {
  int index = layout.index(binder);
  if (index < 0 || !_capture_bit(captures.present, index)) return binder;
  return captures.values[index];
}

/** Replaces named binders in `template` according to `bindings`.
    A sequence binder in list-head position splices its captured `List`;
    `!quote` removes itself and leaves its operand literal. Missing binders are
    retained. A null template returns `nil`, and null bindings return
    `template` unchanged. New structure follows the module pool-chain lifetime
    above.
    Raises: `<alloc-fail>` while constructing replacement `List`s.
*/
meta native List List.replace(List template, List bindings) {
  if (!template) return NULL;
  if (!bindings) return template;
  return _replace(template, bindings);
}

/* Instantiates `input` from an association List. */
static Var _replace(Var input, List bindings) {
  if (input.is_binder() && input != <*> && input != <?>) {
    Var bound = bindings.assoc(input);
    return bound is void ? input : bound;
  }
  if (input is not <list>) return input;
  List lst = input;
  if (!lst) return input;
  Var head = lst.car();
  List tail = lst.cdr();
  if (head == <!quote>) return tail.car();
  int splice = head.is_list_binder() && head != <*> && head != <?>;
  head = _replace(head, bindings);
  tail = _replace(tail, bindings);
  if (splice && head is <list>) return %(@head @tail);
  return %($head @tail);
}

// borrowed patterns

/* Both borrowing owners walk the same graph and differ on one question: how
   long the borrow lasts. Symbols and narrow immediates have value lifetime,
   and `nil` holds no storage, so no later pattern can reuse its address. A
   `String` or long `Atom` is borrowed only when the outermost canonical pool
   owns it, because an equal transient buffer is never interned and its
   address proves nothing. Wide boxes, pointers, and references are never
   borrowed; those patterns prepare a transient plan owned by their lease.

   `permanent_lists` is what separates the two owners. A site keeps its
   program for the life of the process, so it needs a `List` the outermost
   pool owns: a nested pool reuses the storage of its released cells, and an
   identity that belongs to one would let a different pattern answer at the
   same address. The plan cache retires every entry when a level is released,
   so a `List` that is canonical now serves it, and interning gives an equal
   pattern the same cell. */
static int _pattern_borrowable(Var value, int depth, int permanent_lists) {
  if (depth >= 128) return 0;
  switch (value.kind()) {
    case <symbol>: return 1;
    case <pointer>: case <reference>: return 0;
    case <object>: return _object_borrowable(value, depth, permanent_lists);
  }
  return value is not <long> && value is not <ulong> &&
         value is not <llong> && value is not <ullong> &&
         value is not <ldouble>;
}

static int _object_borrowable(Var value, int depth, int permanent_lists) {
  if (value is <lsym>) return String.is_permanent((String) value.pointer());
  if (value is <string>) return String.is_permanent(value);
  if (value is not <list>) return 0;
  if (!value.pointer()) return 1;
  if (permanent_lists && !Pool.is_permanent(value)) return 0;
  // kind and tag prove the raw payload is a List cell
  foreach (Var part, (List) value.pointer())
    if (!_pattern_borrowable(part, depth + 1, permanent_lists)) return 0;
  return 1;
}

/* The plan cache borrows a pattern only until its level is released. */
static int _cache_keyable(Var value, int depth) =>
  _pattern_borrowable(value, depth, 0);

/* A compiler-owned site borrows its pattern for the life of the process. */
static int _pattern_admissible(Var value, int depth) =>
  _pattern_borrowable(value, depth, 1);

/* the plan cache

   The cache owns immutable prepared programs only, never execution state.
   It keys an admitted pattern by its canonical identity, which `Context`
   and the owning pool guarantee for the cache's lifetime; that is why the
   cache is Context-local and is closed before its Context's canonical pool.

   Entries are recycled by deterministic LRU; positive entries are pinned
   while leased, so eviction can never free a program under an active
   execution, and leases carry the entry generation so a stale lease can
   never validate a recycled slot. Raw key zero (the inadmissible null-pointer
   Var) is rejected before the admission memos, whose direct-mapped
   collisions force a fresh admission walk, never a false admission. A
   refusal is memoized as well; refusing only sends a pattern through a
   transient plan, so a stale refusal costs nothing but that preparation. */

#define MATCH_ADMITTED_MEMO 256

typedef struct MatchCacheEntry {
  unsigned long key;
  MatchPlan plan;
  unsigned long generation;
  int occupied, pin_count, bucket_next, lru_prev, lru_next;
} MatchCacheEntry;

struct MatchCache {
  Scope scope;
  MatchCacheEntry *entries;
  int *buckets;
  int capacity, bucket_count, size, lru_head, active_leases;
  unsigned long next_generation, pool_epoch;
  unsigned long admitted_memo[256], refused_memo[256];
};

/** Acquires a lease for a cached prepared pattern.
    `cache` and `lease` must be nonnull, and `owner` names the operation a
    fence diagnostic should report. The lease is initialized on every
    returning path. An admitted pattern reuses or creates an LRU entry; an
    inadmissible pattern gets a transient plan owned by the lease. Returns the
    plan's `MachinePrepare` status, or `MATCH_CACHE_PRESSURE` when every entry
    is pinned. Release the lease after any returned status; releasing the
    inactive pressure lease is a no-op.
    Raises: `<size-limit>` when `pattern` exceeds a lowering limit. Such a
    pattern compiles to no program, so it is never cached and never leased.
    `<alloc-fail>` may also be raised while preparing or growing storage.
*/
int MatchCache.acquire(
  MatchCache m, Var pattern, MatchLease &lease, const char *owner) {
  lease = (MatchLease) {.slot = -1};
  if (!m._admitted(pattern)) return m._transient(pattern, &lease, owner);
  unsigned long key = pattern.u64;
  int slot = m._find(key);
  if (slot >= 0) {
    m._touch(slot);
    m._activate(slot, &lease);
    return m.entries[slot].plan.status;
  }
  slot = m.size < m.capacity ? m._free_slot() : m._victim();
  if (slot < 0) return MATCH_CACHE_PRESSURE;
  MatchPlan plan = m._prepare(pattern, owner);
  if (m.entries[slot].occupied) m._remove(slot);
  m._insert(slot, key, plan);
  m._activate(slot, &lease);
  return plan.status;
}

/* An inadmissible pattern gets a plan its lease owns. */
static int MatchCache._transient(
  MatchCache cache, Var pattern, MatchLease *lease, const char *owner) {
  MatchPlan plan = MatchPlan.prepare(pattern);
  if (plan.status == MACHINE_INELIGIBLE) {
    const char *reason = plan.reason;
    plan.free();
    _raise_ineligible(reason, owner);
  }
  lease.cache = cache;
  lease.transient_plan = plan;
  lease.active = 1;
  cache.active_leases++;
  return plan.status;
}

/* Prepares an entry's plan in the cache's scope. An unusable plan never
   reaches an entry or occupies a cache slot. */
static MatchPlan MatchCache._prepare(
  MatchCache cache, Var pattern, const char *owner) {
  MatchPlan plan = NULL;
  const char *fenced = NULL;
  $scope(&cache.scope) {
    plan = MatchPlan.prepare(pattern);
    if (plan.status == MACHINE_INELIGIBLE) {
      fenced = plan.reason;
      plan.free();
    }
  }
  if (fenced) _raise_ineligible(fenced, owner);
  return plan;
}

/* Installs `plan` under `key` as the most recent entry, with a fresh
   nonzero generation. */
static void MatchCache._insert(
  MatchCache cache, int slot, unsigned long key, MatchPlan plan) {
  MatchCacheEntry *entry = &cache.entries[slot];
  entry.key = key;
  entry.plan = plan;
  entry.pin_count = 0;
  entry.occupied = 1;
  entry.generation = ++cache.next_generation;
  if (!entry.generation) entry.generation = ++cache.next_generation;
  int bucket = cache._bucket(key);
  entry.bucket_next = cache.buckets[bucket];
  cache.buckets[bucket] = slot;
  cache._link_mru(slot);
  cache.size++;
}

static int MatchCache._admitted(MatchCache cache, Var pattern) {
  unsigned long key = pattern.u64;
  if (!key) return 0;
  // a level was released under this table; nothing it held can be trusted
  if (!cache._resync()) return 0;
  int slot = _memo_slot(key);
  if (cache.admitted_memo[slot] == key) return 1;
  if (cache.refused_memo[slot] == key) return 0;
  if (!_cache_keyable(pattern, 0)) {
    cache.refused_memo[slot] = key;
    return 0;
  }
  cache.admitted_memo[slot] = key;
  return 1;
}

/* Drops every entry a released level could have invalidated and adopts the
   new epoch. A pinned entry is still executing, so the table keeps its
   contents and stays refused until a later call finds no lease outstanding. */
static int MatchCache._resync(MatchCache cache) {
  unsigned long epoch = Pool.epoch();
  if (cache.pool_epoch == epoch) return 1;
  if (cache.active_leases) return 0;
  for (int slot = 0; slot < cache.capacity; slot++)
    if (cache.entries[slot].occupied) cache._remove(slot);
  for (int i = 0; i < MATCH_ADMITTED_MEMO; i++) {
    cache.admitted_memo[i] = 0;
    cache.refused_memo[i] = 0;
  }
  cache.pool_epoch = epoch;
  return 1;
}

/* The memo indexes through its own small fold of the raw bits so
   admission consults no cache-table state and the table hash is
   computed only after admission succeeds. */
static int _memo_slot(unsigned long key) =>
  (int) ((key * 0x9e3779b97f4a7c15UL >> 48) & (MATCH_ADMITTED_MEMO - 1));

/** Creates a `MatchCache` retaining up to `capacity` prepared patterns.
    The returned cache owns a named `Scope` and is not synchronized. It borrows
    admitted pattern identities, so dispose it before their owning canonical
    pools. `MatchCache.dispose` is required after every lease is released.
    Raises: `<bad-arg>` when capacity is not positive, `<size-limit>` when its
    storage dimensions cannot be represented, and `<alloc-fail>` when cache
    storage cannot be allocated.
*/
MatchCache MatchCache.new(int capacity) {
  if (capacity <= 0)
    raise %(bad-arg (owner "MatchCache.new") (capacity $capacity));
  if (capacity > (INT_MAX - 1) / 2)
    raise %(size-limit (owner "MatchCache.new") (capacity $capacity));

  Scope owner = Scope.new_named("Match plan cache");
  Scope.push(&owner);
  MatchCache cache = Scope.calloc(1, sizeof(struct MatchCache));
  cache.scope = owner;
  cache.capacity = capacity;
  cache.bucket_count = capacity * 2 + 1;
  cache.lru_head = -1;
  cache.pool_epoch = Pool.epoch();
  cache.entries = Scope.calloc(capacity, sizeof(MatchCacheEntry));
  cache.buckets = Scope.malloc(sizeof(int) * cache.bucket_count);
  for (int i = 0; i < capacity; i++) cache.entries[i].bucket_next = -1;
  for (int i = 0; i < cache.bucket_count; i++) cache.buckets[i] = -1;
  Scope.pop();
  return cache;
}

/** Destroys a `Match` cache with no active leases.
    A null cache is ignored. Disposal frees all plans and cache storage and
    invalidates every alias.
    Raises: `<bad-state>` when a lease remains active. The failure leaves the
    cache intact.
*/
void MatchCache.dispose(MatchCache cache) {
  if (!cache) return;
  if (cache.active_leases) raise %(bad-state (owner "MatchCache.dispose"));

  for (int i = 0; i < cache.capacity; i++) {
    assert(!cache.entries[i].pin_count);
    if (cache.entries[i].occupied) cache.entries[i].plan.free();
  }
  Scope.destroy(cache.scope);
}

/* cache entries

   Each bucket chains its entries through `bucket_next`. The LRU ring links
   every entry: its head is the most recent entry, and the head's
   predecessor the least recent. */

static int MatchCache._find(MatchCache cache, unsigned long key) {
  for (int slot = cache.buckets[cache._bucket(key)]; slot >= 0;
       slot = cache.entries[slot].bucket_next)
    if (cache.entries[slot].occupied && cache.entries[slot].key == key)
      return slot;
  return -1;
}

static int MatchCache._bucket(MatchCache cache, unsigned long key) =>
  (int) (_cache_mix(key) % (unsigned long) cache.bucket_count);

static unsigned long _cache_mix(unsigned long key) {
  key ^= key >> 33;
  key *= 0xff51afd7ed558ccdUL;
  key ^= key >> 33;
  key *= 0xc4ceb9fe1a85ec53UL;
  return key ^ (key >> 33);
}

static void MatchCache._touch(MatchCache cache, int slot) {
  int head = cache.lru_head;
  if (head == slot) return;
  if (cache.entries[head].lru_prev == slot) {
    cache.lru_head = slot;
    return;
  }
  cache._unlink(slot);
  cache._link_mru(slot);
}

static void MatchCache._unlink(MatchCache cache, int slot) {
  MatchCacheEntry *entry = &cache.entries[slot];
  cache.entries[entry.lru_prev].lru_next = entry.lru_next;
  cache.entries[entry.lru_next].lru_prev = entry.lru_prev;
  if (cache.lru_head == slot)
    cache.lru_head = entry.lru_next == slot ? -1 : entry.lru_next;
}

static void MatchCache._link_mru(MatchCache cache, int slot) {
  MatchCacheEntry *entry = &cache.entries[slot];
  int head = cache.lru_head;
  entry.lru_next = head < 0 ? slot : head;
  entry.lru_prev = head < 0 ? slot : cache.entries[head].lru_prev;
  cache.entries[entry.lru_prev].lru_next = slot;
  cache.entries[entry.lru_next].lru_prev = slot;
  cache.lru_head = slot;
}

static int MatchCache._free_slot(MatchCache m) {
  for (int i = 0; i < m.capacity; i++) if (!m.entries[i].occupied) return i;
  return -1;
}

/* The least recent entry that no lease pins, or -1. */
static int MatchCache._victim(MatchCache cache) {
  int slot = cache.entries[cache.lru_head].lru_prev;
  for (int i = 0; i < cache.size; i++) {
    if (!cache.entries[slot].pin_count) return slot;
    slot = cache.entries[slot].lru_prev;
  }
  return -1;
}

static void MatchCache._remove(MatchCache cache, int slot) {
  MatchCacheEntry *entry = &cache.entries[slot];
  assert(entry.occupied && !entry.pin_count);
  int *link = &cache.buckets[cache._bucket(entry.key)];
  while (*link >= 0 && *link != slot) link = &cache.entries[*link].bucket_next;
  assert(*link == slot);
  *link = entry.bucket_next;
  entry.bucket_next = -1;
  cache._unlink(slot);
  entry.plan.free();
  entry.plan = NULL;
  entry.occupied = 0;
  cache.size--;
}

// leases

/* Pins `slot` for `lease`, which records the entry's generation. */
static void MatchCache._activate(MatchCache m, int slot, MatchLease *lease) {
  MatchCacheEntry *entry = &m.entries[slot];
  lease.cache = m;
  lease.generation = entry.generation;
  lease.slot = slot;
  lease.active = 1;
  m.active_leases++;
  entry.pin_count++;
}

/** Releases the prepared program held by `lease`.
    Releasing an inactive lease has no effect. A successful release destroys a
    transient plan or unpins its cached entry and makes the lease inactive.
    Raises: `<bad-arg>` when lease is NULL and `<bad-state>` when its cache or
    entry state is inconsistent. The failure leaves the lease active.
*/
void MatchLease.release(MatchLease *lease) {
  if (!lease) raise %(bad-arg (owner "MatchLease.release"));

  if (!lease.active) return;
  if (lease.transient_plan) {
    if (!lease.cache || lease.cache.active_leases <= 0)
      raise %(bad-state (owner "MatchLease.release"));

    lease.transient_plan.free();
    lease.transient_plan = NULL;
    lease.cache.active_leases--;
    lease.active = 0;
    return;
  }
  MatchCacheEntry *entry = lease._entry();
  if (!entry || lease.cache.active_leases <= 0 || entry.pin_count <= 0)
    raise %(bad-state (owner "MatchLease.release"));

  lease.cache.active_leases--;
  entry.pin_count--;
  lease.active = 0;
}

static MatchPlan MatchLease._plan(MatchLease *lease) {
  if (!lease || !lease.active) return NULL;
  if (lease.transient_plan) return lease.transient_plan;
  MatchCacheEntry *entry = lease._entry();
  return entry ? entry.plan : NULL;
}

/* NULL for a transient lease, or once the slot is empty or recycled under a
   newer generation. */
static MatchCacheEntry *MatchLease._entry(MatchLease *lease) {
  if (!lease.active || lease.transient_plan || !lease.cache) return NULL;
  MatchCache cache = lease.cache;
  if (lease.slot >= 0 && lease.slot < cache.capacity) {
    MatchCacheEntry *entry = &cache.entries[lease.slot];
    if (entry.occupied && entry.generation == lease.generation) return entry;
  }
  return NULL;
}

/* cached consumers

   Each adapter preserves its consumer's result and executes only a prepared
   program. Malformed, cache-pressure, and machine-error cases do not match;
   a fenced pattern raised out of `acquire` and never reaches an adapter. */

/* Declares `$lease` for `$pattern` and the `$status` its acquisition
   returned. */
macro Statement $match.lease(
  Name $lease, Name $status, Expr $cache, Expr $pattern, Expr $owner) {
  MatchLease storage;
  MatchLease *$lease = &storage;
  int $status = $cache.acquire($pattern, *$lease, $owner);
}

/** Matches through `cache` into caller-owned positional storage.
    Returns 1 only after atomically committing a valid buffer. A miss,
    malformed pattern, invalid buffer, cache pressure, or machine error returns
    0 and leaves it unchanged.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or matching.
*/
int MatchCache.try_capture(
  MatchCache cache, List input, Var pattern, MatchCaptureBuffer &?captures,
  const char *owner) {
  $match.lease(lease, status, cache, pattern, owner);
  int result = 0;
  MatchPlan plan = lease._plan();
  if (status == MACHINE_PREPARED) result = plan.try_capture(input, captures);
  lease.release();
  return result == 1;
}

/** Matches through `cache`, writing bindings on success.
    `out_bindings` must be nonnull. Returns 0 and leaves it unchanged for a
    miss, malformed pattern, cache pressure, or machine error. Successful
    binding shape and order follow `MatchPlan.execute`.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing, or publishing.
*/
int MatchCache.try_match(
  MatchCache cache, List input, Var pattern, List &?out_bindings,
  const char *owner) {
  $match.lease(lease, status, cache, pattern, owner);
  int result = 0;
  MatchPlan plan = lease._plan();
  if (status == MACHINE_PREPARED) result = plan.try_match(input, out_bindings);
  lease.release();
  return result == 1;
}

/** Searches through `cache`, writing the first match and bindings.
    Both outputs must be nonnull. Returns 0 and leaves them unchanged on a
    miss, malformed pattern, cache pressure, or machine error. Traversal order
    follows `MatchPlan.try_search`.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or constructing bindings.
*/
int MatchCache.try_search(
  MatchCache cache, List input, Var pattern, Var &?out_match,
  List &?out_bindings, const char *owner) {
  $match.lease(lease, status, cache, pattern, owner);
  int result = 0;
  MatchPlan plan = lease._plan();
  if (status == MACHINE_PREPARED)
    result = plan.try_search(input, out_match, out_bindings);
  lease.release();
  return result == 1;
}

/** Searches through `cache`, writing every match.
    `out_results` must be nonnull. It receives the reverse-visitation result
    `List`, or `nil` when there are no matches, the pattern is malformed, cache
    pressure prevents execution, or the machine fails. Returns 1 exactly when
    that `List` is nonempty.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or constructing results.
*/
int MatchCache.search(
  MatchCache cache, List input, Var pattern, List &out_results,
  const char *owner) {
  $match.lease(lease, status, cache, pattern, owner);
  List results = NULL;
  MatchPlan plan = lease._plan();
  if (status == MACHINE_PREPARED) plan.search(input, results);
  lease.release();
  out_results = results;
  return results != NULL;
}

/** `Match`-replaces through `cache`, writing the replacement on success.
    `out` must be nonnull. Returns 0 and leaves it unchanged on a miss,
    malformed pattern, cache pressure, or machine error. The successful result
    may be any `Var`.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing, or replacing.
*/
int MatchCache.try_match_replace(
  MatchCache cache, List input, Var pattern, Var template, Var &?out,
  const char *owner) {
  $match.lease(lease, status, cache, pattern, owner);
  int result = 0;
  MatchPlan plan = lease._plan();
  if (status == MACHINE_PREPARED)
    result = plan.try_match_replace(input, template, out);
  lease.release();
  return result == 1;
}

/** Replaces every match through `cache` from the leaves upward.
    `out` must be nonnull. A completed prepared traversal returns 1 and writes
    its result even when nothing matched. A malformed pattern, cache pressure,
    or machine error returns 0 and writes `input` unchanged.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, traversing, or replacing.
*/
int MatchCache.search_replace(
  MatchCache cache, List input, Var pattern, Var template, List &out,
  const char *owner) {
  $match.lease(lease, status, cache, pattern, owner);
  int answered = status != MACHINE_PREPARED, List result = input;
  MatchPlan plan = lease._plan();
  if (status == MACHINE_PREPARED)
    answered = plan.search_replace(input, template, result) >= 0;
  lease.release();
  out = result;
  return status == MACHINE_PREPARED && answered;
}

/* default caches

   The active default cache is Context-local when a Context is open and
   otherwise thread-local, and it is created on first use. Entries may borrow
   runtime canonical identities, so a flush must precede the release of a
   pool that owns an admitted pattern. */

typedef struct MatchContextState {
  struct MatchContextState *prev, MatchCache cache;
} *MatchContextState;

typedef struct MatchThreadState {
  MatchCache plan_cache;
  MatchContextState context_top;
} *MatchThreadState;

static threaded struct MatchThreadState match_thread;

static MatchThreadState _thread(void) => &match_thread;

static MatchCache _plan_cache(void) {
  MatchCache *slot = _default_slot();
  if (!*slot) *slot = MatchCache.new(256);
  x2c_match_initialize();
  return *slot;
}

/* The top Context's cache when a Context is open, or else the thread's. */
static MatchCache *_default_slot(void) {
  MatchThreadState state = _thread();
  return state.context_top ? &state.context_top.cache : &state.plan_cache;
}

/** Destroys the active `Context`-local or thread-local `Match` cache.
    A missing cache is ignored; the next `Match` recreates it lazily. Static
    compiler capture sites are unaffected.
    Raises: `<bad-state>` when a lease remains active. The failure leaves the
    cache installed.
*/
void MatchCache.flush_default(void) {
  MatchCache *slot = _default_slot();
  if (!*slot) return;
  (*slot).dispose();
  *slot = NULL;
}

/** Opens one `Context`-local default `Match`-cache state.
    The returned opaque token becomes the top of a thread-local LIFO stack;
    its cache is created only on first use. The token is allocated in the
    active `Scope` and must be passed to `MatchCache.context_close` before that
    `Scope` ends.
    Raises: `<alloc-fail>` when the state cannot be allocated.
*/
void *MatchCache.context_open(void) {
  MatchContextState state = Scope.malloc(sizeof(struct MatchContextState));
  state.prev = _thread().context_top;
  state.cache = NULL;
  _thread().context_top = state;
  return state;
}

/** Disposes and removes the top `Context`'s default `Match` cache.
    A null token is ignored. Successful close restores the previous default;
    the token storage remains owned by its `Context` `Scope`.
    Raises: `<bad-state>` when `token` is not the top state or its cache has an
    active lease. The failure leaves the state installed.
*/
void MatchCache.context_close(void *token) {
  MatchContextState state = token;
  if (!state) return;
  if (_thread().context_top != state)
    raise %(bad-state (owner "MatchCache.context_close"));

  if (state.cache) state.cache.dispose();
  _thread().context_top = state.prev;
}

/** Disposes this thread's default `Match` plan cache.
    `x2c_thread_state_release` calls it before `Scope` releases the `Scope`
    that holds that cache; a thread that never matched has no cache and
    nothing happens. All default-cache leases and `Context` states must
    already be closed.
    Raises: `<bad-state>` when a lease remains active.
*/
void x2c_match_thread_release(void) {
  MatchThreadState state = &match_thread;
  if (!state.plan_cache) return;
  state.plan_cache.dispose();
  state.plan_cache = NULL;
}

/* capture sites

   The compiler gives each complete static pattern its own site, which holds
   one immutable plan in `Match`-owned process storage until shutdown. Only
   the first call takes a lock, to prepare that plan; `plan` is published
   last and read with acquire ordering, so a site that already holds a plan
   needs no synchronization. */

static Scope match_capture_site_scope;
static Block match_capture_sites;

static pthread_mutex_t match_site_mutex =
  (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;

/** Matches through one compiler-owned static capture site.
    Its first admissible pattern permanently binds the site; direct C callers
    must not reuse one site for different patterns. `site` must be
    zero-initialized static storage and `pattern` must contain only values that
    remain live through `Match` shutdown. A pattern the site cannot retain
    takes the ordinary runtime route, with the same result, and the site
    records that refusal once, so later calls take that route directly.
    Returns 1 only after atomically committing `captures`; invalid arguments,
    malformed patterns, misses, and machine errors return 0 without changing
    it.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    publishing or matching.
*/
int x2c_match_site_try_capture(
  MatchCaptureSite *site, List input, Var pattern,
  MatchCaptureBuffer *captures) {
  if (!captures) return 0;
  MatchPlan plan = _site_published(site, pattern);
  // a pattern the site cannot retain takes the ordinary runtime route
  if (!plan) return x2c_match_try_capture(input, pattern, captures);
  if (plan.status == MACHINE_MALFORMED) return 0;
  return _plan_prepared(plan, "match") &&
         _capture_buffer_valid(plan.layout, captures) &&
         plan._capture(input, captures, NULL) == 1;
}

/* Returns this site's plan, publishing it on the first call and answering
   NULL for a site whose pattern it cannot retain. The refusal is recorded on
   the site, so a pattern the site rejects costs two atomic loads per call
   instead of the registry lock and a fresh admissibility walk. */
static MatchPlan _site_published(MatchCaptureSite *site, Var pattern) {
  if (!site) return NULL;
  MatchPlan plan = __atomic_load_n(&site.plan, __ATOMIC_ACQUIRE);
  if (plan) return plan;
  if (__atomic_load_n(&site.refused, __ATOMIC_ACQUIRE)) return NULL;
  return _site_publish(site, pattern);
}

/* Prepares one site once, under the lock that also guards the site
   registry. Every later call sees the published plan and skips this. */
static MatchPlan _site_publish(MatchCaptureSite *site, Var pattern) {
  _site_lock();
  // preparation allocates, and an allocation failure never returns here
  defer _site_unlock();
  if (!site.plan) _site_prepare(site, pattern);
  return site.plan;
}

static void _site_prepare(MatchCaptureSite *site, Var pattern) {
  if (!_pattern_admissible(pattern, 0)) {
    __atomic_store_n(&site.refused, 1, __ATOMIC_RELEASE);
    return;
  }
  _sites_initialize();
  MatchPlan plan = NULL;
  $scope(&match_capture_site_scope) {
    plan = MatchPlan.prepare(pattern);
    match_capture_sites.push(&site);
  }
  /* Normalizing a guard allocates cells in the pool active at this first
     call, and the layout keeps them for the life of the process. */
  if (plan.layout.normalized is <list>) List.try_own(plan.layout.normalized);
  __atomic_store_n(&site.plan, plan, __ATOMIC_RELEASE);
}

static void _sites_initialize(void) {
  if (match_capture_site_scope) return;
  match_capture_site_scope = Scope.new_named("Match source-site plans");
  $scope(&match_capture_site_scope) {
    match_capture_sites = Block.new(sizeof(MatchCaptureSite *));
  }
  x2c_match_initialize();
}

static void _site_lock(void) {
  _thread_check(pthread_mutex_lock(&match_site_mutex), "lock source site");
}

static void _site_unlock(void) {
  _thread_check(pthread_mutex_unlock(&match_site_mutex), "unlock source site");
}

/* A native thread primitive that fails leaves the registry in an unknown
   state, so the process reports it and aborts. */
static void _thread_check(int status, const char *action) {
  if (!status) return;
  fprintf(stderr, "Match: could not %s\n", action);
  abort();
}

/** Reports whether a compiler-owned site can retain `pattern`.
    A site borrows its pattern's values for the life of the process, so only a
    graph of values that outlives every call qualifies.
*/
int x2c_match_pattern_retainable(Var pattern) =>
  _pattern_admissible(pattern, 0);

/** Returns the process-lifetime plan for one compiler-owned site.
    The first retainable pattern binds the site permanently. A pattern the site
    cannot retain returns NULL; an ineligible one returns its fenced plan so
    the caller can name the fence.
    Raises: `<alloc-fail>` while publishing.
*/
MatchPlan x2c_match_site_prepare(MatchCaptureSite *site, Var pattern) =>
  _site_published(site, pattern);

/* site consumers

   Each operation follows its `List` counterpart. A pattern the site cannot
   retain, or an ineligible one, takes that ordinary runtime route, which has
   the same result and names the public operation when it reports a fence. */

/* The plan this site holds, publishing it on the first call, or NULL for
   the ordinary runtime route. */
static MatchPlan _site_plan(MatchCaptureSite *site, Var pattern) {
  MatchPlan plan = _site_published(site, pattern);
  return plan && plan.status != MACHINE_INELIGIBLE ? plan : NULL;
}

/** Matches through one compiler-owned site, writing bindings on success.
    Results follow `List.try_match`.
*/
int x2c_match_site_try_match(
  MatchCaptureSite *site, List input, Var pat, List *out_bindings) {
  MatchPlan plan = _site_plan(site, pat);
  if (!plan) return input.try_match(pat, *out_bindings);
  if (!out_bindings) return 0;
  return plan.try_match(input, *out_bindings) == 1;
}

/** Returns bindings through one compiler-owned site, or `nil` on a miss.
    Results follow `List.match`.
*/
List x2c_match_site_match(MatchCaptureSite *site, List input, Var pat) {
  List bindings;
  if (!x2c_match_site_try_match(site, input, pat, &bindings)) return NULL;
  return bindings ? bindings : %(());
}

/** Searches through one compiler-owned site, writing the first match.
    Results follow `List.try_search`.
*/
int x2c_match_site_try_search(
  MatchCaptureSite *site, List input, Var pat, Var *out_match,
  List *out_bindings) {
  MatchPlan plan = _site_plan(site, pat);
  if (!plan) return input.try_search(pat, *out_match, *out_bindings);
  if (!out_match || !out_bindings) return 0;
  return plan.try_search(input, *out_match, *out_bindings) == 1;
}

/** Returns every matching subtree through one compiler-owned site.
    Results follow `List.search`.
*/
List x2c_match_site_search(MatchCaptureSite *site, List input, Var pat) {
  MatchPlan plan = _site_plan(site, pat);
  if (!plan) return input.search(pat);
  List results = NULL;
  plan.search(input, results);
  return results;
}

/** `Match`-replaces through one compiler-owned site.
    Results follow `List.try_match_replace`.
*/
int x2c_match_site_try_match_replace(
  MatchCaptureSite *site, List input, Var pat, Var template, Var *out) {
  MatchPlan plan = _site_plan(site, pat);
  if (!plan) return input.try_match_replace(pat, template, *out);
  if (!out) return 0;
  return plan.try_match_replace(input, template, *out) == 1;
}

/** Returns the `List` replacement through one compiler-owned site.
    Results follow `List.match_replace`.
*/
List x2c_match_site_match_replace(
  MatchCaptureSite *site, List input, Var pat, Var template) {
  Var result;
  if (!x2c_match_site_try_match_replace(site, input, pat, template, &result))
    return input;
  return result is <list> ? result : NULL;
}

/** Replaces every match through one compiler-owned site.
    Results follow `List.search_replace`.
*/
List x2c_match_site_search_replace(
  MatchCaptureSite *site, List input, Var pat, Var template) {
  MatchPlan plan = _site_plan(site, pat);
  if (!plan) return input.search_replace(pat, template);
  List result = input;
  plan.search_replace(input, template, result);
  return result;
}

/* the List.match family

   Each operation prepares its pattern through the active default cache on
   first use and reuses the program afterward. `try_*` output pointers are
   required, remain unchanged on failure, and receive `nil` bindings for a
   successful match with no user binders. */

/** Matches a runtime pattern into positional storage.
    The active default cache prepares the pattern on its first use and
    reuses that program afterward. Returns 1 on success and 0 on a miss,
    malformed pattern, invalid buffer, cache pressure, or machine error. A
    nonnull buffer is written atomically as described by
    `MatchCaptureBuffer`; NULL returns 0.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or matching.
*/
int x2c_match_try_capture(
  List input, Var pattern, MatchCaptureBuffer *captures) {
  if (!captures) return 0;
  return _plan_cache().try_capture(input, pattern, *captures, "match");
}

/** Matches `input` against `pat`, writing bindings on success.
    Returns 1 on a match and writes a reverse-slot-order association `List`, or
    returns 0 and leaves `out_bindings` unchanged. A successful binder-free
    match writes `nil`. A null output pointer returns 0.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing captures, or publishing bindings.
*/
int List.try_match(List input, Var pat, List &?out_bindings) => out_bindings &&
  _plan_cache().try_match(input, pat, out_bindings, "List.try_match");

/** Returns bindings when `input` matches `pat`, or `nil` on a miss.
    A binder-free success returns the nonnull `%(())` sentinel
    with no associations. Binding order and failures follow `List.try_match`.
*/
List List.match(List input, Var pat) {
  List bindings;
  if (!input.try_match(pat, bindings)) return NULL;
  return bindings ? bindings : %(());
}

/** Matches `input` and writes the instantiated `template` on success.
    The output may be any `Var`, including typed `nil` or a scalar. A template
    that is one binder the match left unbound, such as the binder of an `!or`
    alternative another alternative satisfied, writes that binder. Returns 0
    for a miss, malformed pattern, invalid output, or machine error and leaves
    `out` unchanged.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing, or replacing.
*/
int List.try_match_replace(List input, Var pat, Var template, Var &?out) =>
  out && _plan_cache().try_match_replace(
    input, pat, template, out, "List.try_match_replace");

/** Returns the `List` replacement when `input` matches `pat`.
    A miss returns `input` unchanged. A successful scalar replacement cannot
    inhabit the `List` result and returns `nil`. Matching and replacement
    failures follow `List.try_match_replace`.
*/
meta native List List.match_replace(List input, Var pat, Var template) {
  Var result;
  if (!input.try_match_replace(pat, template, result)) return input;
  return result is <list> ? result : NULL;
}

/** Returns every matching subtree of `input` with its bindings.
    Each result begins with `(* matched)` followed by reverse-slot-order binder
    pairs. Traversal visits a `List`'s head, then tail, then the `List` itself;
    results are prepended and therefore returned in reverse visitation order.
    Explicit `nil` values are nodes, but a proper `List`'s terminal cdr is not.
    A miss, malformed pattern, or machine error returns `nil`.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or constructing results.
*/
List List.search(List input, Var pat) {
  List results;
  _plan_cache().search(input, pat, results, "List.search");
  return results;
}

/** Searches `input` for `pat`, writing the first match and bindings.
    The depth-first order is head, tail, then containing `List`, with the same
    explicit-`nil` rule as `List.search`. Returns 1 on success; otherwise
    returns 0 and leaves both outputs unchanged. Either null output returns 0.
    Raises: the same causes as `List.search`.
*/
int List.try_search(
  List input, Var pat, Var &?out_match, List &?out_bindings) =>
    out_match && out_bindings && _plan_cache().try_search(
      input, pat, out_match, out_bindings, "List.try_search");

/** Replaces every matching subtree in `input` from the leaves upward.
    Children are rewritten before their reconstructed containing `List` is
    tested. A miss, malformed pattern, or machine error returns `input`
    unchanged. New structure follows the module pool-chain lifetime above.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, traversing, or replacing.
*/
List List.search_replace(List input, Var pat, Var template) {
  List result;
  _plan_cache().search_replace(
    input, pat, template, result, "List.search_replace");
  return result;
}

// lifecycle

static pthread_once_t match_shutdown_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;

/** Registers process-wide `Match` cleanup exactly once.
    Repeated calls have no effect. Failure of the native once primitive writes
    a diagnostic and aborts the process.
    Raises: `<alloc-fail>` or `<size-limit>` while registering the shutdown
    hook.
*/
void x2c_match_initialize(void) {
  int status = pthread_once(&match_shutdown_once, _register_shutdown_once);
  _thread_check(status, "register shutdown");
}

static void _register_shutdown_once(void) {
  Scope.shutdown_hook(_shutdown);
}

static void _shutdown(void) {
  x2c_match_thread_release();
  _sites_shutdown();
}

static void _sites_shutdown(void) {
  if (!match_capture_site_scope) return;
  MatchCaptureSite **sites = match_capture_sites != NULL
                           ? match_capture_sites.bytes : NULL;
  for (size_t i = 0; i < match_capture_sites.length; i++) {
    MatchCaptureSite *site = sites[i];
    if (!site || !site.plan) continue;
    site.plan.free();
    site.plan = NULL;
  }
  if (match_capture_sites != NULL) match_capture_sites.free();
  match_capture_site_scope.destroy();
  match_capture_site_scope = NULL;
}

/** Initializes fresh caller-owned storage without touching unused fixed
    arrays. The caller must eventually dispose any materialization scratch.
*/
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

/** Frees reusable materialization scratch. Finish active execution first;
    this does not clear invocation state.
*/
void MatchMachine.dispose(MatchMachine m) {
  if (m.scratch) Scope.free(m.scratch);
  m.scratch = NULL;
  m.scratch_capacity = 0;
}
