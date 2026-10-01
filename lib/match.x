/*  match.x -- pattern matching and transformation utilities for lists

    Copyright (c) 2025 Gary William Flake

    Match owns the pattern vocabulary, capture layouts, and the execution of
    plans that `match-plan.x` prepares and `match-cache.x` retains. Core
    matching runs only prepared plans; `unittest/match-recursive.x` is the
    reference matcher of the differential tests. An invocation commits
    captures to caller-owned storage only after the whole match succeeds.

    Association-List results are published from committed captures. New
    Lists canonicalize through the active pool chain; a result may belong to
    an ancestor and lives until its owning pool is released.
 */

#pragma once

$(import "error-macros.xmacro")
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
#include "match-plan.x"
#include "match-cache.x"
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

typedef struct NormalizedCell {
  List original;
  Var head;
} NormalizedCell;

/* Normalizes siblings iteratively and retains every unchanged suffix. */
static List _normalize_elements(List elements) {
  Block spine = $auto(Block.new(sizeof(NormalizedCell)));
  for (List cell = elements; cell; cell = cell.cdr()) {
    Var head = cell.car();
    NormalizedCell row = {
      cell, head is <list> ? (Var) _normalize_pattern(head) : head};
    spine.push(&row);
  }
  List out = NULL;
  for (size_t i = spine.length; i > 0; i--) {
    NormalizedCell row = ((NormalizedCell *) spine.bytes)[i - 1];
    out = row.head == row.original.car() && out == row.original.cdr()
      ? row.original : cons(row.head, out);
  }
  return out;
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
    MatchSlots slots = layout._slots(pattern);
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

static MatchSlots MatchCaptureLayout._slots(
  MatchCaptureLayout m, Var pattern) {
  if (_named_binder(pattern)) return m._binder_slot(pattern);
  if (pattern is not <list> || pattern.is_nil()) return (MatchSlots) {0, 0};
  List list = pattern;
  Var head = list.car();
  List args = list.cdr();
  if (head == <!quote>) return (MatchSlots) {0, 0};
  if (head == <x2c-dyn>)
    return (MatchSlots) {0, m._sequence_slots(args).possible};
  if (!head.is_match_op()) return m._sequence_slots(list);
  return m._guard_slots(head, args);
}

/* `(!set BINDER PAT)` is the one-operand capture form, and a negation
   binds nothing on every match. */
static MatchSlots MatchCaptureLayout._guard_slots(
  MatchCaptureLayout m, Var op, List args) {
  MatchSlots slots = {0, 0};
  if (args && args.cdr() && _named_binder(args.car())) {
    slots = m._binder_slot(args.car());
    args = args.cdr();
  }
  if (op == <!and>) return _union(slots, m._sequence_slots(args));
  if (op == <!not>) {
    MatchSlots operands = m._sequence_slots(args);
    return (MatchSlots) {0, slots.possible | operands.possible};
  }
  if (op == <!set> && args.len() == 1)
    return _union(slots, m._sequence_slots(args));
  if (op == <!or> || op == <!set>) return _union(slots, m._choice_slots(args));
  return slots;
}

/* Every element of a sequence matches, so each one's definite slots are
   definite. */
static MatchSlots MatchCaptureLayout._sequence_slots(
  MatchCaptureLayout m, List patterns) {
  MatchSlots slots = {0, 0};
  foreach (Var pattern, patterns) slots = _union(slots, m._slots(pattern));
  return slots;
}

/* One alternative matches, so only the slots every one binds are
   definite. */
static MatchSlots MatchCaptureLayout._choice_slots(
  MatchCaptureLayout m, List patterns) {
  MatchSlots slots = {0, 0};
  int first = 1;
  foreach (Var pattern, patterns) {
    MatchSlots part = m._slots(pattern);
    slots.possible |= part.possible;
    slots.definite = first ? part.definite : slots.definite & part.definite;
    first = 0;
  }
  return slots;
}

static MatchSlots MatchCaptureLayout._binder_slot(
  MatchCaptureLayout m, Var binder) {
  int index = m._find(binder);
  assert(index >= 0);
  unsigned long bit = 1UL << index;
  return (MatchSlots) {bit, bit};
}

static MatchSlots _union(MatchSlots a, MatchSlots b) =>
  (MatchSlots) {a.definite | b.definite, a.possible | b.possible};

static int MatchCaptureLayout._find(MatchCaptureLayout layout, Atom binder) {
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
  layout ? layout._binders(layout.definite) : NULL;

/** Returns possible binders in canonical positional order.
    A null layout or no possible binders returns `nil`. The canonical result
    follows the module pool-chain lifetime above.
    Raises: `<alloc-fail>` while constructing the `List`.
*/
List MatchCaptureLayout.possible_list(MatchCaptureLayout layout) =>
  layout ? layout._binders(layout.possible) : NULL;

/* The binders of the `included` slots, in slot order. */
static List MatchCaptureLayout._binders(
  MatchCaptureLayout layout, unsigned long included) {
  List binders = NULL;
  for (int i = layout.binder_count - 1; i >= 0; i--)
    if (_capture_bit(included, i)) binders = cons(layout.binders[i], binders);
  return binders;
}

/** Returns the canonical slot for `binder`, or -1 when it is absent.
    A null layout returns -1. Comparison uses exact `Atom` identity.
*/
int MatchCaptureLayout.index(MatchCaptureLayout layout, Atom binder) =>
  layout ? layout._find(binder) : -1;

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

/* plan execution

   Only a prepared plan runs. An entry point raises the fence of an
   ineligible plan, and a malformed plan answers no match. */

/** Raises the fence an ineligible plan crossed, naming `owner`.
    This is the one place an ineligible pattern is reported. Such a pattern
    compiles to no program, so answering "no match" would be wrong and no
    caller could tell it from a real miss. `reason` is the plan's static
    category string.
    Raises: `<size-limit>` naming `owner` and the fence.
*/
void MatchPlan.raise_ineligible(const char *reason, const char *owner) {
  String fence = String.new(reason), site = String.new(owner);
  raise %(size-limit (owner $site) (fence $fence));
}

/* Entry-point guard over an already prepared plan; `plan` stays owned by
   its caller. Malformed patterns keep their categorized no-match. */
static int MatchPlan._prepared(MatchPlan plan, const char *owner) {
  if (plan && plan.status == MACHINE_INELIGIBLE)
    MatchPlan.raise_ineligible(plan.reason, owner);
  return plan && plan.status == MACHINE_PREPARED;
}

static int MatchCaptureLayout._buffer_valid(
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
  if (!m._prepared("MatchPlan.execute_capture") ||
      !m.layout._buffer_valid(captures))
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
  if (!plan._prepared("MatchPlan.execute")) return -1;
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
  if (result == 1) out = mm.layout._publish(&captures);
  return result;
}

/* The committed captures as an association List in reverse slot order. */
static List MatchCaptureLayout._publish(
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
  if (!plan._prepared("MatchPlan.try_search") || !out_match ||
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
  if (!plan._prepared("MatchPlan.search") || !out_results) return -1;
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
  if (!plan._prepared("MatchPlan.search_replace") || !out) return -1;
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
  cons(%(* $node), walk.plan.layout._publish(walk.captures));

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
  walk.bindings = walk.plan.layout._publish(walk.captures);
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
  if (!plan._prepared("MatchPlan.try_match_replace") || !out) return -1;
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

typedef struct ReplacementCell {
  Var value;
  int splice;
} ReplacementCell;

/* Instantiates `input` from committed captures. */
static Var _capture_replace(
  Var input, MatchCaptureLayout layout, MatchCaptureBuffer *captures) {
  if (_named_binder(input)) return layout._captured(captures, input);
  if (input is not <list>) return input;
  List list = input;
  if (!list) return input;
  if (list.car() == <!quote>) return list.cadr();
  Block spine = $auto(Block.new(sizeof(ReplacementCell)));
  Var tail = (List) NULL;
  for (; list; list = list.cdr()) {
    Var head = list.car();
    if (head == <!quote>) {
      tail = list.cadr();
      break;
    }
    ReplacementCell row = {
      _capture_replace(head, layout, captures),
      head.is_list_binder() && head != <*> && head != <?>
    };
    spine.push(&row);
  }
  for (size_t i = spine.length; i > 0; i--) {
    ReplacementCell row = ((ReplacementCell *) spine.bytes)[i - 1];
    Var head = row.value;
    if (row.splice && head is <list>) tail = %(@head @tail);
    else tail = %($head @tail);
  }
  return tail;
}

/* The value captured for `binder`, or the binder when the match left it
   unbound. */
static Var MatchCaptureLayout._captured(
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
  List list = input;
  if (!list) return input;
  if (list.car() == <!quote>) return list.cadr();
  Block spine = $auto(Block.new(sizeof(ReplacementCell)));
  Var tail = (List) NULL;
  for (; list; list = list.cdr()) {
    Var head = list.car();
    if (head == <!quote>) {
      tail = list.cadr();
      break;
    }
    ReplacementCell row = {
      _replace(head, bindings),
      head.is_list_binder() && head != <*> && head != <?>
    };
    spine.push(&row);
  }
  for (size_t i = spine.length; i > 0; i--) {
    ReplacementCell row = ((ReplacementCell *) spine.bytes)[i - 1];
    Var head = row.value;
    if (row.splice && head is <list>) tail = %(@head @tail);
    else tail = %($head @tail);
  }
  return tail;
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

/** Reports whether a plan may borrow `pattern` by its canonical identity.
    `permanent_lists` requires every `List` in it to belong to the outermost
    pool, as a plan kept for the life of the process does. Without it, a
    `List` that is canonical now qualifies until its pool level is released.
*/
int MatchPlan.borrowable(Var pattern, int permanent_lists) =>
  _pattern_borrowable(pattern, 0, permanent_lists);

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
  MatchPlan plan = site._published(pattern);
  // a pattern the site cannot retain takes the ordinary runtime route
  if (!plan) return x2c_match_try_capture(input, pattern, captures);
  if (plan.status == MACHINE_MALFORMED) return 0;
  return plan._prepared("match") &&
         plan.layout._buffer_valid(captures) &&
         plan._capture(input, captures, NULL) == 1;
}

/* Returns this site's plan, publishing it on the first call and answering
   NULL for a site whose pattern it cannot retain. The refusal is recorded on
   the site, so a pattern the site rejects costs two atomic loads per call
   instead of the registry lock and a fresh admissibility walk. */
static MatchPlan MatchCaptureSite._published(
  MatchCaptureSite *site, Var pattern) {
  if (!site) return NULL;
  MatchPlan plan = __atomic_load_n(&site.plan, __ATOMIC_ACQUIRE);
  if (plan) return plan;
  if (__atomic_load_n(&site.refused, __ATOMIC_ACQUIRE)) return NULL;
  return site._publish(pattern);
}

/* Prepares one site once, under the lock that also guards the site
   registry. Every later call sees the published plan and skips this. */
static MatchPlan MatchCaptureSite._publish(MatchCaptureSite *m, Var pattern) {
  _site_lock();
  // preparation allocates, and an allocation failure never returns here
  defer _site_unlock();
  if (!m.plan) m._prepare(pattern);
  return m.plan;
}

static void MatchCaptureSite._prepare(MatchCaptureSite *site, Var pattern) {
  if (!MatchPlan.borrowable(pattern, 1)) {
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
  MatchPlan.borrowable(pattern, 1);

/** Returns the process-lifetime plan for one compiler-owned site.
    The first retainable pattern binds the site permanently. A pattern the site
    cannot retain returns NULL; an ineligible one returns its fenced plan so
    the caller can name the fence.
    Raises: `<alloc-fail>` while publishing.
*/
MatchPlan x2c_match_site_prepare(MatchCaptureSite *site, Var pattern) =>
  site._published(pattern);

/* site consumers

   Each operation follows its `List` counterpart. A pattern the site cannot
   retain, or an ineligible one, takes that ordinary runtime route, which has
   the same result and names the public operation when it reports a fence. */

/* The plan this site holds, publishing it on the first call, or NULL for
   the ordinary runtime route. */
static MatchPlan MatchCaptureSite._plan(MatchCaptureSite *site, Var pattern) {
  MatchPlan plan = site._published(pattern);
  return plan && plan.status != MACHINE_INELIGIBLE ? plan : NULL;
}

/** Matches through one compiler-owned site, writing bindings on success.
    Results follow `List.try_match`.
*/
int x2c_match_site_try_match(
  MatchCaptureSite *site, List input, Var pat, List *out_bindings) {
  MatchPlan plan = site._plan(pat);
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
  MatchPlan plan = site._plan(pat);
  if (!plan) return input.try_search(pat, *out_match, *out_bindings);
  if (!out_match || !out_bindings) return 0;
  return plan.try_search(input, *out_match, *out_bindings) == 1;
}

/** Returns every matching subtree through one compiler-owned site.
    Results follow `List.search`.
*/
List x2c_match_site_search(MatchCaptureSite *site, List input, Var pat) {
  MatchPlan plan = site._plan(pat);
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
  MatchPlan plan = site._plan(pat);
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
  MatchPlan plan = site._plan(pat);
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
  return MatchCache.current().try_capture(input, pattern, *captures, "match");
}

/** Matches `input` against `pat`, writing bindings on success.
    Returns 1 on a match and writes a reverse-slot-order association `List`, or
    returns 0 and leaves `out_bindings` unchanged. A successful binder-free
    match writes `nil`. A null output pointer returns 0.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing captures, or publishing bindings.
*/
int List.try_match(List input, Var pat, List &?out_bindings) => out_bindings &&
  MatchCache.current().try_match(input, pat, out_bindings, "List.try_match");

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
  out && MatchCache.current().try_match_replace(
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
  MatchCache.current().search(input, pat, results, "List.search");
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
    out_match && out_bindings && MatchCache.current().try_search(
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
  MatchCache.current().search_replace(
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
