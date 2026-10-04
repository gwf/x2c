/*  match-plan.x -- lowering Match patterns to prepared plans

    Copyright (c) 2026 Gary William Flake.

    A MatchPlan is the prepared form of one pattern: its capture layout and
    a program in the wordcode of `machine.x`. A plan owns both and borrows
    the canonical values in its pattern. Preparation records why a pattern
    has no program and raises for none of them; `match.x` runs the plan.
*/

#pragma once

#include "match.x"

#pragma private

#include <assert.h>
#include "scope.x"
#include "list.x"

/* lowering to Match words

   One recursive pass compiles a normalized pattern to machine words.
   Ordinary elements fuse against the segment cursor, star-free plain
   sublists descend inline through spare registers, and guards, quoted
   forms, and starred or deep sublists keep call frames. Stars, ordered
   alternatives, and negation are branch and call templates over generic
   words; there is no STAR, OR, or NOT instruction. */

#define MATCH_SEGMENT_MAX 128
#define MATCH_INLINE_MAX   64

/* Owns the builder and failure sites the enclosing block has yet to patch,
   with the call-frame depth of the block under construction. */
typedef struct MatchLower {
  MachineBuilder b;
  int *sites, site_count, site_capacity, depth;
} MatchLower;

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
  plan.key_count = 0;
  Var normalized = plan.layout.normalized;
  if (plan.status == MACHINE_PREPARED) plan._lower(normalized);
  if (plan.status == MACHINE_PREPARED) plan._record_keys(normalized);
  return plan;
}

/* Lowers the normalized pattern and freezes an exact-sized program in the
   caller's scope. The builder interns the layout's binders first, so its
   slots are the layout's. */
static void MatchPlan._lower(MatchPlan plan, Var pattern) {
  MatchLower l = {.b = MachineBuilder.new(), .depth = 1};
  defer l.b.free();
  for (int i = 0; i < plan.layout.binder_count; i++)
    if (l.b.binder(plan.layout.binders[i]) != i) break;
  l.b.root = l.b.status == MACHINE_PREPARED ? l._compile_value(pattern) : -1;
  if (l.b.root < 0) l._fail("lowering");
  plan.status = l.b.status;
  plan.reason = l.b.reason;
  if (plan.status == MACHINE_PREPARED) plan.program = l.b.freeze();
  if (l.sites) Scope.free(l.sites);
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
static int MatchLower._compile_value(MatchLower &l, Var pattern) {
  if (pattern.is_atom_binder()) return l._compile_binder(pattern);
  if (pattern is not <list>) return l._compile_literal(pattern);
  List list = pattern;
  if (list && list.car().is_match_op())
    return l._compile_guard(list.car(), list.cdr());
  if (list && _is_list_literal(list)) return l._compile_literal_list(list);
  return l._compile_segment(list);
}

static int MatchLower._compile_binder(MatchLower &l, Var binder) {
  int entry = l.b.length;
  if (binder == <?>) {
    l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
    return l._stopped() ? -1 : entry;
  }
  int base = l.site_count;
  return l._emit_binder(binder) ? l._finish(entry, base) : -1;
}

/* Binds a fresh slot to the current value, or compares a bound one. */
static int MatchLower._emit_binder(MatchLower &l, Var binder) {
  if (binder == <?>) return 1;
  int slot = l.b.binder(binder);
  if (slot < 0) return 0;
  int valid = l.b.emit(MW_SLOT_VALID, slot, 0, 0, 0, -1);
  l.b.emit(MW_SLOT_SET_VALUE, slot, 0, 0, 0, 0);
  int done = l.b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  if (valid < 0 || done < 0) return 0;
  int compare = l.b.length;
  if (!l._fail_site(MW_SLOT_EQ_VALUE, slot, 0, 0, 0)) return 0;
  l.b.set_target(valid, compare);
  l.b.set_target(done, l.b.length);
  return 1;
}

static int MatchLower._compile_literal(MatchLower &l, Var pattern) {
  int entry = l.b.length, base = l.site_count;
  return l._emit_literal(pattern) ? l._finish(entry, base) : -1;
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
static int MatchLower._emit_leaf_value(MatchLower &l, Var pattern) {
  if (pattern.is_atom_binder()) return l._emit_binder(pattern);
  return l._emit_literal(pattern);
}

/* Compares the current value with the constant `pattern`. */
static int MatchLower._emit_literal(MatchLower &l, Var pattern) {
  int constant = l.b.constant(pattern);
  return constant >= 0 &&
    l._fail_site(MW_EQ_VALUE_CONST, constant, 0, 0, _compare_mode(pattern));
}

/* A List with no binder and no guard at any depth. */
static int _is_list_literal(List pat) {
  foreach (Var head, pat) {
    if (head.is_binder() || head.is_match_op()) return 0;
    if (head is <list> && !_is_list_literal(head)) return 0;
  }
  return 1;
}

/* A binder-free literal list compares by canonical identity first and falls
   back to the elementwise segment, mirroring the recursive matcher's
   interned-list fast path without collapsing boxed-equal elements into a
   bit comparison. */
static int MatchLower._compile_literal_list(MatchLower &l, List pattern) {
  int constant = l.b.constant(pattern);
  if (constant < 0) return -1;
  int entry = l.b.length;
  int miss = l.b.emit(MW_EQ_VALUE_BITS, constant, 0, 0, 0, -1);
  l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  int segment = l._compile_segment(pattern);
  if (segment < 0) return -1;
  l.b.set_target(miss, segment);
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
static int MatchLower._compile_child(MatchLower &l, Var pattern) {
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
  MatchLower &l, int op, int a, int b, int c, int d) {
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
static void MatchLower._patch_sites(MatchLower &l, int base, int target) {
  for (int i = base; i < l.site_count; i++)
    l.b.set_target(l.sites[i], target);
  l.site_count = base;
}

/* Ends the block at `entry` with its success and failure returns and
   returns `entry`, or -1. */
static int MatchLower._finish(MatchLower &l, int entry, int base) {
  l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  return l._finish_failure(entry, base);
}

static int MatchLower._finish_failure(MatchLower &l, int entry, int base) {
  int failure = l.b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  if (failure < 0) return -1;
  l._patch_sites(base, failure);
  return entry;
}

static int MatchLower._emit_call(MatchLower &l, int child, int mode, int reg) {
  if (l.b.emit(MW_CALL, child, mode, reg, 0, 0) < 0) return 0;
  return l._fail_site(MW_BR_FAIL, 0, 0, 0, 0);
}

/* Records the first ineligibility reason and returns the failed entry. */
static int MatchLower._fail(MatchLower &l, const char *reason) {
  if (l.b.status == MACHINE_PREPARED) {
    l.b.status = MACHINE_INELIGIBLE;
    l.b.reason = reason;
  }
  return -1;
}

static int MatchLower._stopped(MatchLower &l) =>
  l.b.status != MACHINE_PREPARED;

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

static int MatchLower._compile_guard(MatchLower &l, Var op, List args) {
  if (op == <!or>) return l._compile_or(args);
  if (op == <!not>) return l._compile_not(args);
  if (op == <!is>) return l._compile_is(args);
  if (op == <!set>) return l._compile_set(args);
  if (op == <!and>) return l._compile_and(args);
  return l._compile_quote(args);
}

/* Compiles each operand that is not an atom as a child block. */
static int MatchLower._guard_parts(
  MatchLower &l, List args, MatchParts &parts) {
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

static int MatchLower._emit_operand(
  MatchLower &l, MatchParts &parts, int i) =>
  l._emit_test(parts.elements[i], parts.entries[i]);

/* Tests the current value: an atom `test` inline when `child` is negative,
   or else by calling its child block. */
static int MatchLower._emit_test(MatchLower &l, Var test, int child) {
  if (child < 0) return l._emit_leaf_value(test);
  return l._emit_call(child, MACHINE_CALL_CURRENT, 0);
}

/* Ordered alternatives are static call, branch, and return templates: every
   failed arm returns through its paired undo and order call-entry mark, and
   the first successful arm returns immediately as the local cut. */
static int MatchLower._compile_or(MatchLower &l, List args) {
  MatchParts operands;
  if (!l._guard_parts(args, operands)) return -1;
  int entry = l.b.length, base = l.site_count;
  for (int i = 0; i < operands.count; i++) {
    l._patch_sites(base, l.b.length);
    if (!l._emit_operand(operands, i)) return -1;
    if (l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0) < 0) return -1;
  }
  return l._finish_failure(entry, base);
}

/* Negation uses one frame-local mark and rolls the journal back on both
   inverted outcomes, so no child binding can leak. */
static int MatchLower._compile_not(MatchLower &l, List args) {
  MatchParts operands;
  if (!l._guard_parts(args, operands)) return -1;
  int entry = l.b.length, base = l.site_count;
  l.b.emit(MW_MARK, 0, 0, 0, 0, 0);
  int successes[MATCH_SEGMENT_MAX];
  for (int i = 0; i < operands.count; i++) {
    l._patch_sites(base, l.b.length);
    if (!l._emit_operand(operands, i)) return -1;
    successes[i] = l.b.emit(MW_JUMP, 0, 0, 0, 0, -1);
    if (successes[i] < 0) return -1;
  }
  int all_failed = l.b.length;
  l._patch_sites(base, all_failed);
  l.b.emit(MW_ROLLBACK, 0, MACHINE_ROLLBACK_RESTORE, 0, 0, 0);
  l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  int rejected = l.b.length;
  l.b.patch(successes, operands.count, rejected);
  l.b.emit(MW_ROLLBACK, 0, MACHINE_ROLLBACK_RESTORE, 0, 0, 0);
  if (l.b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0) < 0) return -1;
  return entry;
}

/* `(!set BINDER TEST)` binds and tests in one block, calling a List TEST
   as a child block; any other set is a list of ordered alternatives. */
static int MatchLower._compile_set(MatchLower &l, List args) {
  if (!_set_binds(args)) return l._compile_or(args);
  Var (binder, test) = args;
  int child = test is <list> ? l._compile_child(test) : -1;
  if (test is <list> && child < 0) return -1;
  int entry = l.b.length, base = l.site_count;
  return l._emit_binder(binder) && l._emit_test(test, child)
       ? l._finish(entry, base) : -1;
}

/* `(!set BINDER TEST)`, rather than a set of alternatives. */
static int _set_binds(List args) =>
  args && args.cdr() && !args.cddr() && args.car().is_atom_binder();

/* Every operand must match the current value, in order. */
static int MatchLower._compile_and(MatchLower &l, List args) {
  MatchParts operands;
  if (!l._guard_parts(args, operands)) return -1;
  int entry = l.b.length, base = l.site_count;
  for (int i = 0; i < operands.count; i++)
    if (!l._emit_operand(operands, i)) return -1;
  return l._finish(entry, base);
}

/* The runtime compares only one quoted operand. */
static int MatchLower._compile_quote(MatchLower &l, List args) {
  if (!args || args.cdr()) return l._fail("quote-arity");
  return l._compile_literal(args.car());
}

/* type tests

   `!is` tests the current value against a fixed vocabulary: its binder or
   operator kind, whether it is an atom, or its tag. An unknown shape fails
   at execution. */

static int MatchLower._compile_is(MatchLower &l, List args) {
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

static int MatchLower._is_kind(MatchLower &l, int kind) {
  int entry = l.b.length, base = l.site_count;
  return l._fail_site(MW_MATCH_KIND, 0, kind, 0, 0)
       ? l._finish(entry, base) : -1;
}

/* `(atom)` holds for any value whose tag is not `list`. */
static int MatchLower._is_atom(MatchLower &l) {
  int entry = l.b.length, constant = l.b.constant(<list>);
  if (constant < 0) return -1;
  int hit = l.b.emit(MW_TAG, constant, 0, 0, 0, -1);
  int is_list = l.b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  if (hit < 0 || is_list < 0) return -1;
  int success = l.b.length;
  l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  int failure = l.b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  if (failure < 0) return -1;
  l.b.set_target(hit, success);
  l.b.set_target(is_list, failure);
  return entry;
}

/* `(type TAG)` canonicalizes varray and vmap to the public tags before
   freezing the constant; a TAG that is not a Symbol never matches. */
static int MatchLower._is_type(MatchLower &l, Var type) {
  Symbol tag = _canonical_type_tag(type is <symbol> ? type.symbol() : 0);
  if (!tag) return l._never();
  int entry = l.b.length, base = l.site_count, constant = l.b.constant(tag);
  return constant >= 0 && l._fail_site(MW_TAG, constant, 0, 0, 0)
       ? l._finish(entry, base) : -1;
}

static inline Symbol _canonical_type_tag(Symbol tag) {
  if (tag == <varray>) return <array>;
  if (tag == <vmap>)   return <map>;
  return tag;
}

/* A block that always fails. */
static int MatchLower._never(MatchLower &l) {
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

static int MatchLower._compile_segment(MatchLower &l, List pattern) {
  MatchSegment s;
  s.nested.count = s.nested.used = 0;
  if (!l._segment_prefix(s, pattern) || !l._segment_star(s.star)) return -1;
  int entry = l.b.length, base = l.site_count;
  if (!l._fail_site(MW_INPUT_LIST, 0, 0, 0, 0) || !l._emit_prefix(s) ||
      !l._segment_end(s.star))
    return -1;
  return l._finish_failure(entry, base);
}

/* Compiles the children of the prefix, which runs up to the first star.
   An atom executes inline against the cursor head; a star-free plain
   sublist descends inline through the next register; guards, quoted forms,
   literal lists, and starred or deep sublists keep a call frame with an
   independent register bank. */
static int MatchLower._segment_prefix(
  MatchLower &l, MatchSegment &s, List pattern) {
  int n = 0, List at = pattern;
  while (at && !at.car().is_list_binder()) {
    if (n >= MATCH_SEGMENT_MAX) return l._fail("segment-width") + 1;
    Var part = at.car();
    s.prefix.elements[n] = part;
    if (part is not <list>) s.prefix.entries[n++] = -1;
    else if (_inline_descend_ok(part, 0)) {
      if (!l._compile_nested(part, 1, s.nested)) return 0;
      s.prefix.entries[n++] = -2;
    }
    else {
      s.prefix.entries[n] = l._compile_child(part);
      if (s.prefix.entries[n++] < 0) return 0;
    }
    at = at.cdr();
  }
  s.prefix.count = n;
  s.star.cell = at;
  return 1;
}

/* A star-free plain nested segment may execute in the enclosing frame
   through the bank's next cursor register: stars are the only other
   consumers of registers one and two and always run in their own frame;
   guards and quoted forms keep call frames, and literal lists keep the
   canonical-identity path. */
static int _inline_descend_ok(List child, int reg) {
  if (reg + 1 >= MACHINE_CURSOR_REGS || !child ||
      child.car().is_match_op() || _is_list_literal(child))
    return 0;
  foreach (Var part, child) if (part.is_list_binder()) return 0;
  return 1;
}

/* Precompiles every framed child block reachable through inline descents,
   in traversal order. */
static int MatchLower._compile_nested(
  MatchLower &l, List pattern, int reg, MatchInlinePlan &nested) {
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
static int MatchLower._segment_star(MatchLower &l, MatchStar &star) {
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
static int MatchLower._compile_tail(MatchLower &l, List pattern) {
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

static int MatchLower._emit_prefix(MatchLower &l, MatchSegment &s) {
  for (int i = 0; i < s.prefix.count; i++) if (!l._emit_part(s, i)) return 0;
  return 1;
}

static int MatchLower._emit_part(MatchLower &l, MatchSegment &s, int i) {
  int entry = s.prefix.entries[i];
  if (entry == -1) return l._emit_head_leaf(s.prefix.elements[i], 0);
  if (entry == -2) return l._emit_descend(s.prefix.elements[i], 0, s.nested);
  return l._emit_framed(entry, 0);
}

/* Tests the element at the cursor head of `reg`: `?` skips it, an atom
   binder binds or compares it, and a literal compares it. */
static int MatchLower._emit_head_leaf(MatchLower &l, Var part, int reg) {
  if (part == <?>) return l._fail_site(MW_SKIP_HEAD, 0, reg, 0, 0);
  if (part.is_atom_binder()) {
    int slot = l.b.binder(part);
    if (slot < 0) return 0;
    return l._fail_site(MW_BIND_HEAD, slot, reg, 0, 0);
  }
  int constant = l.b.constant(part);
  if (constant < 0) return 0;
  int mode = _compare_mode(part);
  return l._fail_site(MW_EQ_HEAD_CONST, constant, reg, 0, mode);
}

/* Descends into the sublist at the cursor head of `reg` through the next
   register, then advances past it. */
static int MatchLower._emit_descend(
  MatchLower &l, List child, int reg, MatchInlinePlan &nested) =>
  l._fail_site(MW_DESCEND, 0, reg, reg + 1, 0) &&
  l._emit_inline_segment(child, reg + 1, nested) &&
  l.b.emit(MW_ADVANCE, reg, 0, 0, 0, 0) >= 0;

/* Calls a child block on the cursor head of `reg`, which must exist, then
   advances past it. */
static int MatchLower._emit_framed(MatchLower &l, int entry, int reg) =>
  l._fail_site(MW_NONNIL, reg, 0, 0, 0) &&
  l._emit_call(entry, MACHINE_CALL_HEAD, reg) &&
  l.b.emit(MW_ADVANCE, reg, 0, 0, 0, 0) >= 0;

/* Emits an inline sublist through `reg`; its elements must end with it. */
static int MatchLower._emit_inline_segment(
  MatchLower &l, List pattern, int reg, MatchInlinePlan &nested) {
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

static int MatchLower._segment_end(MatchLower &l, MatchStar &star) {
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
static int MatchLower._final_star(MatchLower &l, int slot) {
  if (slot < 0) return l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0) >= 0;

  int valid = l.b.emit(MW_SLOT_VALID, slot, 0, 0, 0, -1);
  l.b.emit(MW_CURSOR_VALUE, 0, 1, 0, 0, 0);
  l.b.emit(MW_SLOT_SET_VALUE, slot, 0, 0, 0, 0);
  int fresh = l.b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  if (valid < 0 || fresh < 0) return 0;

  int existing = l.b.length;
  int is_span = l.b.emit(MW_SLOT_IS_SPAN, slot, 0, 0, 0, -1);
  l.b.emit(MW_CURSOR_VALUE, 0, 0, 0, 0, 0);
  if (!l._fail_site(MW_SLOT_EQ_VALUE, slot, 0, 0, 0)) return 0;
  int value_done = l.b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  if (is_span < 0 || value_done < 0) return 0;

  int compare_span = l.b.length;
  if (!l._fail_site(MW_SLOT_EQ_FINAL_IDENTITY, slot, 0, 1, 0)) return 0;
  l.b.emit(MW_CURSOR_VALUE, 0, 1, 0, 0, 0);
  l.b.emit(MW_SLOT_SET_VALUE, slot, 1, 0, 0, 0);

  int success = l.b.length;
  if (l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0) < 0) return 0;
  l.b.set_target(valid, existing);
  l.b.set_target(is_span, compare_span);
  l.b.set_target(fresh, success);
  l.b.set_target(value_done, success);
  return 1;
}

/* An interior star enumerates shortest-first splits. An anchored star pairs
   monotonic split and probe cursors through one fused SCAN; an unanchored
   star advances one optional split per retry. A unique unreferenced binder
   defers its span until the tail succeeds, and a repeated binder compares
   the candidate range in place. */
static int MatchLower._search_star(MatchLower &l, MatchStar &star) {
  int slot = star.slot, loop = l._star_loop(star);
  if (loop < 0) return 0;
  int valid = -1;
  if (slot >= 0) valid = l.b.emit(MW_SLOT_VALID, slot, 0, 0, 0, -1);
  int fresh_failed = l._star_fresh(star);
  if (fresh_failed < 0) return 0;

  int mismatch = -1, existing_failed = -1;
  if (slot >= 0) {
    int compare = l.b.length;
    mismatch = l.b.emit(MW_SLOT_EQ_PREFIX, slot, 0, 1, 0, -1);
    existing_failed = l._star_tail(star);
    if (mismatch < 0 || existing_failed < 0) return 0;
    l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
    l.b.set_target(valid, compare);
  }

  int retry = l.b.length;
  l.b.set_target(mismatch, retry);
  l.b.set_target(fresh_failed, retry);
  l.b.set_target(existing_failed, retry);
  return l._star_retry(star, loop);
}

/* Starts the split cursors and emits the loop head, which fails the
   segment once no split remains. Returns the head's site, or -1. */
static int MatchLower._star_loop(MatchLower &l, MatchStar &star) {
  int anchored = star.anchored;
  int constant = anchored ? l.b.constant(star.anchor) : -1;
  if (anchored && constant < 0) return -1;
  int mode = anchored ? _compare_mode(star.anchor) : MACHINE_COMPARE_BITS;
  l.b.emit(MW_MARK, 0, 0, 0, 0, 0);
  l.b.emit(MW_MOVE, 1, 0, 0, 0, 0);
  if (anchored) {
    l.b.emit(MW_MOVE, 2, 1, 0, 0, 0);
    l.b.emit(MW_OFFSET, 2, star.offset, 0, 0, 0);
  }
  else
    l.b.emit(MW_SET_ACTIVE, 0, 1, 0, 0, 0);

  int loop = l.b.length;
  int emitted = anchored
    ? l._fail_site(MW_SCAN, 1, 2, constant, mode)
    : l._fail_site(MW_REQUIRE_ACTIVE, 0, 0, 0, 0);
  return emitted ? loop : -1;
}

/* A fresh binder takes the split's span before the tail runs or, when
   delayed, after it succeeds. Returns the tail's failure branch, or -1. */
static int MatchLower._star_fresh(MatchLower &l, MatchStar &star) {
  int slot = star.slot;
  if (slot >= 0 && !star.delayed)
    l.b.emit(MW_SLOT_SET_SPAN, slot, 0, 1, 0, 0);
  int failed = l._star_tail(star);
  if (failed < 0) return -1;
  if (slot >= 0 && star.delayed)
    l.b.emit(MW_SLOT_SET_SPAN, slot, 0, 1, 0, 0);
  l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  return failed;
}

/* Calls the tail at the split cursor; returns its failure branch. */
static int MatchLower._star_tail(MatchLower &l, MatchStar &star) {
  l.b.emit(MW_CALL, star.entry, MACHINE_CALL_CURSOR, 1, 0, 0);
  return l.b.emit(MW_BR_FAIL, 0, 0, 0, 0, -1);
}

/* Undoes the failed split's bindings and moves to the next split. */
static int MatchLower._star_retry(MatchLower &l, MatchStar &star, int loop) {
  l.b.emit(MW_ROLLBACK, 0, MACHINE_ROLLBACK_RETRY, 0, 0, 0);
  if (star.anchored) {
    l.b.emit(MW_ADVANCE, 1, 0, 0, 0, 0);
    l.b.emit(MW_ADVANCE, 2, 0, 0, 0, 0);
  }
  else
    l.b.emit(MW_ADVANCE_OPTIONAL, 1, 0, 0, 0, 0);
  return l.b.emit(MW_JUMP, 0, 0, 0, 0, loop) >= 0 && !l._stopped();
}

/* input keys

   When a pattern fixes how a matching List begins, its plan records each
   way as a key: the first element, and the first later element of the
   fixed prefix that is a constant or a List beginning with one. `Match`
   checks the keys before it takes a machine, so an input that begins
   otherwise costs a few comparisons. The program tests every key itself,
   so the check never refuses an input the plan matches. */

/* What a pattern constrains: the current value itself, the first element
   of a List, or that element with one later element. */
enum { MATCH_KEY_VALUE, MATCH_KEY_LIST, MATCH_KEY_INPUT };

typedef struct MatchKeys {
  MatchKey keys[MATCH_KEY_MAX];
  int count;
} MatchKeys;

/* Records the keys of a normalized pattern; a pattern that fixes none, or
   more than the plan holds, records none. */
static void MatchPlan._record_keys(MatchPlan plan, Var pattern) {
  MatchKeys found = {.count = 0};
  if (!_keys(pattern, MATCH_KEY_INPUT, found)) return;
  plan.key_bits = 1;
  for (int i = 0; i < found.count; i++) {
    MatchKey key = found.keys[i];
    plan.keys[i] = key;
    if (!_bits_unique(key.head) || (key.index && !_bits_unique(key.inner)))
      plan.key_bits = 0;
  }
  plan.key_count = found.count;
}

/* Adds the keys `pattern` fixes in `mode`, or returns 0. In value and List
   modes a key's `head` is the value, and `nested` says which mode found
   it. Alternatives contribute their keys only when every one has some. */
static int _keys(Var pattern, int mode, MatchKeys &keys) {
  if (pattern is not <list>)
    return mode == MATCH_KEY_VALUE && !pattern.is_binder() &&
           keys._add((MatchKey) {pattern, void, 0, 0});
  List list = pattern;
  if (!list) return 0;
  Var op = list.car();
  List args = list.cdr();
  if (!op.is_match_op())
    return mode != MATCH_KEY_VALUE && _segment_keys(list, mode, keys);
  if (op == <!set> && _set_binds(args)) return _keys(args.cadr(), mode, keys);
  if (op == <!or> || op == <!set>) {
    foreach (Var arm, args) if (!_keys(arm, mode, keys)) return 0;
    return args != NULL;
  }
  if (op != <!and>) return 0;
  int count = keys.count;
  foreach (Var operand, args) {
    if (_keys(operand, mode, keys)) return 1;
    keys.count = count;
  }
  return 0;
}

/* A segment fixes its first element when that is a value; in input mode
   each value pairs with every key of the first later element that has
   some. */
static int _segment_keys(List pattern, int mode, MatchKeys &keys) {
  MatchKeys heads = {.count = 0}, inner = {.count = 0};
  if (!_keys(pattern.car(), MATCH_KEY_VALUE, heads)) return 0;
  int index = mode == MATCH_KEY_INPUT ? _inner_keys(pattern.cdr(), inner) : 0;
  for (int i = 0; i < heads.count; i++) {
    Var head = heads.keys[i].head;
    if (!index && !keys._add((MatchKey) {head, void, 0, 1})) return 0;
    for (int j = 0; j < inner.count; j++) {
      MatchKey later = inner.keys[j];
      if (!keys._add((MatchKey) {head, later.head, index, later.nested}))
        return 0;
    }
  }
  return 1;
}

/* Adds the keys of the first element of `rest`, before any star, that has
   some, and returns its index after the segment's head, or 0. */
static int _inner_keys(List rest, MatchKeys &inner) {
  int index = 1;
  foreach (Var part, rest) {
    if (part.is_list_binder()) return 0;
    if (_keys(part, MATCH_KEY_VALUE, inner)) return index;
    inner.count = 0;
    if (_keys(part, MATCH_KEY_LIST, inner)) return index;
    inner.count = 0;
    index++;
  }
  return 0;
}

static int MatchKeys._add(MatchKeys &keys, MatchKey key) {
  if (keys.count >= MATCH_KEY_MAX) return 0;
  keys.keys[keys.count++] = key;
  return 1;
}
