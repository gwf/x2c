/*  match.x -- pattern matching and transformation utilities for lists

    Copyright (c) 2025 Gary William Flake

    Every guard except !quote accepts an optional leading binder. Nil is
    typed `List` data: it may be matched at the root or stored as an explicit
    searchable element.  A proper `List`'s implicit terminal cdr is traversal
    structure and is not reported as an extra search node.

    `try_*` output pointers are required, remain unchanged on failure, and
    write `nil` bindings for a successful match with no user binders.

    MatchPlan is the runtime-internal prepared form of one pattern: a
    single analysis pass normalizes, categorizes, and lowers the pattern
    to shared wordcode from `machine.x`; the internal `match-machine.x`
    decoder executes it, and `freeze` publishes an exact-sized immutable
    program. Preparation returns PREPARED, INELIGIBLE(reason), or
    MALFORMED(reason). Invalid
    sigil-leading `Atom` names report MALFORMED("binder-name"); a raw leading
    list binder inside a guard retains its categorized malformed result; more
    than MACHINE_BINDER_MAX distinct binders reports
    MALFORMED("binder-capacity"). Preparation reports every status, but no
    entry point can answer for an INELIGIBLE plan, so each one raises
    `<size-limit>` naming the fence instead of reporting no match. Core
    matching executes only compiled plans; `match-recursive.x` is the
    optional reference implementation used by the differential tests.
    A MatchPlan owns an immutable layout and program but borrows the canonical
    values embedded in its pattern. MatchCaptureSite owns its plan until
    `Match`
    shutdown. Each invocation uses caller-owned capture storage and publishes
    it only after the complete match succeeds.
    Public association-`List` results are published from committed captures.
    New `List`s canonicalize through the active pool chain; a result may belong
    to an ancestor and lives until its owning pool is released.
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
    pattern binds it permanently; `Match` shutdown frees the
    plan and clears the
    site. Direct callers must not reuse a site for another pattern.
*/
typedef struct MatchCaptureSite {
  MatchPlan plan;
} MatchCaptureSite;

#pragma private

#include <pthread.h>
#include <stdlib.h>

#pragma public

/** Matches a runtime pattern into positional storage.
    The pattern is prepared for this call alone, so a caller that repeats one
    pattern pays one preparation each time. Returns 1 on success and 0 on a
    miss, malformed pattern, invalid buffer, or machine error. A nonnull
    buffer is written atomically as described by `MatchCaptureBuffer`; NULL
    returns 0.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing or matching.
*/
int x2c_match_try_capture(
  List input, Var pattern, MatchCaptureBuffer *captures) {
  if (!captures) return 0;
  MatchPlan plan = _transient_plan(pattern, "match");
  int result = plan.try_capture(input, captures);
  plan.free();
  return result == 1;
}

/* Matches through one compiler-proven static source-pattern site.

    Static sites retain one immutable plan in Match-owned process storage.
    The compiler gives each complete static pattern its own site; `pattern`
    initializes that site on its first call.

    Only the one preparation takes a lock. `plan` is published last and read
    with acquire ordering, so a site that already holds a plan needs no
    synchronization.
*/
/** Matches through one compiler-owned static capture site.
    Its first admissible pattern permanently binds the site; direct C callers
    must not reuse one site for different patterns. `site` must be
    zero-initialized static storage and `pattern` must contain only values that
    remain live through `Match` shutdown. Returns 1 only after atomically
    committing `captures`; invalid arguments, malformed or inadmissible
    patterns, misses, and machine errors return 0 without changing it.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    publishing or matching.
*/
int x2c_match_site_try_capture(
  MatchCaptureSite *site, List input, Var pattern,
  MatchCaptureBuffer *captures) {
  if (!site || !captures) return 0;
  MatchPlan plan = __atomic_load_n(&site.plan, __ATOMIC_ACQUIRE);
  if (!plan) plan = _capture_site_publish(site, pattern);
  if (!plan) return 0;
  if (plan.status == MACHINE_MALFORMED) return 0;
  MatchCaptureLayout layout = plan.layout;
  if (_plan_prepared(plan, "match") &&
      _capture_buffer_valid(layout, captures)) {
    int result = plan._capture(input, captures, NULL);
    return result == 1;
  }
  return 0;
}

/* Returns the plan this site holds, publishing it on the first call. A
   pattern the site cannot retain, and an ineligible one, return NULL so the
   caller falls back to the ordinary per-call route. That route has the same
   result and names the public operation when it reports the fence. */
static MatchPlan _site_plan(MatchCaptureSite *site, Var pattern) {
  if (!site) return NULL;
  MatchPlan plan = __atomic_load_n(&site.plan, __ATOMIC_ACQUIRE);
  if (!plan) plan = _capture_site_publish(site, pattern);
  return plan && plan.status != MACHINE_INELIGIBLE ? plan : NULL;
}

/** Matches through one compiler-owned site, writing bindings on success.
    Results follow `List.try_match`.
*/
int x2c_match_site_try_match(
  MatchCaptureSite *site, List input, Var pat, List *out_bindings) {
  MatchPlan plan = _site_plan(site, pat);
  if (!plan) return input.try_match(pat, out_bindings);
  if (!out_bindings) return 0;
  return plan.try_match(input, out_bindings) == 1;
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
  if (!plan) return input.try_search(pat, out_match, out_bindings);
  if (!out_match || !out_bindings) return 0;
  return plan.try_search(input, out_match, out_bindings) == 1;
}

/** Returns every matching subtree through one compiler-owned site.
    Results follow `List.search`.
*/
List x2c_match_site_search(MatchCaptureSite *site, List input, Var pat) {
  MatchPlan plan = _site_plan(site, pat);
  if (!plan) return input.search(pat);
  List results = NULL;
  plan.search(input, &results);
  return results;
}

/** `Match`-replaces through one compiler-owned site.
    Results follow `List.try_match_replace`.
*/
int x2c_match_site_try_match_replace(
  MatchCaptureSite *site, List input, Var pat, Var template, Var *out) {
  MatchPlan plan = _site_plan(site, pat);
  if (!plan) return input.try_match_replace(pat, template, out);
  if (!out) return 0;
  return plan.try_match_replace(input, template, out) == 1;
}

/** Returns the `List` replacement through one compiler-owned site.
    Results follow `List.match_replace`.
*/
List x2c_match_site_match_replace(
  MatchCaptureSite *site, List input, Var pat, Var template) {
  Var result;
  if (!x2c_match_site_try_match_replace(site, input, pat, template, &result))
    return input;
  return result is <list> ? result.list() : NULL;
}

/** Replaces every match through one compiler-owned site.
    Results follow `List.search_replace`.
*/
List x2c_match_site_search_replace(
  MatchCaptureSite *site, List input, Var pat, Var template) {
  MatchPlan plan = _site_plan(site, pat);
  if (!plan) return input.search_replace(pat, template);
  List result = input;
  plan.search_replace(input, template, &result);
  return result;
}

#pragma private
#include <stddef.h>
#include <assert.h>
#include "var.x"
#include "list.x"
#include "atom.x"
#include "exception.x"
#include "symbol.x"
#include "scope.x"
#include "block.x"

macro Statement $match.machine(Name $instance, Expr $stats)
  using $storage => {
  struct MatchMachine $storage;
  MatchMachine $instance = &$storage;
  $instance.open();
  $instance.stats = $stats;
}

/* Based on Peter Norvig's implementation:
    https://github.com/norvig/paip-lisp/blob/main/lisp/patmatch.lisp

    `_normalize_pattern` rewrites `(OP BINDER PAT ...)` into
    `(!set BINDER (OP PAT ...))` for every operator except `!quote`. Binder
    captures stay consistent whether the binder appears explicitly or as the
    first argument to a guard.
*/

// pattern classification

static List _normalize_elements(List elements) {
  if (!elements) return NULL;
  Var head = elements.car(), normalized_head = head;
  if (head is <list>) normalized_head = _normalize_pattern(head);
  List tail = elements.cdr(), normalized_tail = _normalize_elements(tail);
  if (normalized_head == head && normalized_tail == tail) return elements;
  return %($normalized_head @normalized_tail);
}

static List _normalize_pattern(List pattern) {
  if (!pattern || car(pattern) == <!quote>) return pattern;
  List normalized = _normalize_elements(pattern);
  Var op = car(normalized);
  List args = cdr(normalized);
  if (!op.is_match_op() || op == <!set> || op == <!quote> || !args)
    return normalized;
  Var binder = car(args);
  if (!binder.is_binder()) return normalized;
  List rest = cdr(args);
  return %(!set $binder ($op @rest));
}

static int _is_list_literal(List pat) {
  if (!pat) return 1;
  Var head = car(pat);
  if (head.is_binder() || head.is_match_op()) return 0;
  if (head is not <list>) return _is_list_literal(cdr(pat));
  return _is_list_literal(head) && _is_list_literal(cdr(pat));
}

static int _binder_kind(Var atom) {
  if (!atom.is_atom()) return 0;
  String spelling = atom.str(), int length = spelling.len();
  if (!length) return 0;
  char sigil = spelling[0];
  if (sigil != '?' && sigil != '*') return 0;
  if (length == 1) return sigil;
  unsigned char first = (unsigned char) spelling[1];
  if (!((first >= 'A' && first <= 'Z') ||
        (first >= 'a' && first <= 'z') || first == '_'))
    return 0;
  for (int i = 2; i < length; i++) {
    unsigned char ch = (unsigned char) spelling[i];
    if (!((ch >= 'A' && ch <= 'Z') ||
          (ch >= 'a' && ch <= 'z') ||
          (ch >= '0' && ch <= '9') || ch == '_'))
      return 0;
  }
  return sigil;
}

/** Reports whether `atom` is a valid named or anonymous `?` binder.
    Raises: `<alloc-fail>` while decoding a compact `Atom`.
*/
int Var.is_atom_binder(Var atom) => _binder_kind(atom) == '?';

/** Reports whether `atom` is a valid named or anonymous `*` binder.
    Raises: `<alloc-fail>` while decoding a compact `Atom`.
*/
int Var.is_list_binder(Var atom) => _binder_kind(atom) == '*';

/** Reports whether `atom` is either valid `Match` binder form.
    Raises: `<alloc-fail>` while decoding a compact `Atom`.
*/
int Var.is_binder(Var atom) => _binder_kind(atom) != 0;

/** Reports whether `atom` is a compact built-in `Match` guard operator. */
int Var.is_match_op(Var atom) {
  if (atom is not <symbol>) return 0;
  Symbol symbol = atom;
  switch (symbol) {
    case <!is>: case <!set>: case <!or>: case <!and>: case <!not>:
    case <!quote>:
      return 1;
  }
  return 0;
}

static int _reserved_match_predicate(Var atom) => atom is <symbol> &&
         (atom == <?binder?> || atom == <*binder?> || atom == <!op?>);

static int _malformed_binder_atom(Var atom) => atom.is_atom() &&
         (Atom.first(atom) == '?' || Atom.first(atom) == '*') &&
         !atom.is_binder();

// canonical capture layout

typedef struct MatchLayoutBuilder {
  Atom binders[MACHINE_BINDER_MAX];
  int count, malformed_binder, leading_list_binder, past_capacity;
} MatchLayoutBuilder;

static int _named_binder(Var value) =>
  value.is_binder() && value != <?> && value != <*>;

/* Returns the slot for `binder`, or -1 once the pattern is past capacity. */
static int _layout_builder_add(MatchLayoutBuilder *builder, Atom binder) {
  for (int i = 0; i < builder.count; i++)
    if (builder.binders[i].u64 == binder.u64) return i;
  if (builder.count >= MACHINE_BINDER_MAX) return -1;
  builder.binders[builder.count] = binder;
  return builder.count++;
}

/* Validate and collect the raw pattern in one lexical preorder walk. !quote
   is opaque. Compact matcher predicates are control vocabulary only
   as the final operand of !is. The compiler's dynamic-value marker retains
   binders in its literal children without treating the marker as data. */
static void _layout_collect(MatchLayoutBuilder *builder, Var pattern) {
  if (pattern is not <list>) {
    if (_malformed_binder_atom(pattern)) builder->malformed_binder = 1;
    else if (_named_binder(pattern) &&
             _layout_builder_add(builder, pattern) < 0)
      builder->past_capacity = 1;
    return;
  }
  if (pattern.is_nil()) return;
  List list = pattern;
  Var head = car(list);
  if (head == <!quote>) return;
  if (head.is_match_op()) {
    List args = cdr(list);
    if (args && car(args).is_list_binder()) builder->leading_list_binder = 1;
  }
  List parts = head == <x2c-dyn> ? cdr(list) : list;
  int predicate_form = head == <!is>;
  for (List at = parts; at; at = cdr(at)) {
    Var part = car(at);
    if (predicate_form && !cdr(at) && _reserved_match_predicate(part))
      continue;
    _layout_collect(builder, part);
    if (builder->malformed_binder) return;
  }
}

static int _capture_bit(unsigned long bits, int index) =>
  (int) ((bits >> index) & 1UL);

static int _layout_index(MatchCaptureLayout layout, Atom binder) {
  for (int i = 0; i < layout.binder_count; i++)
    if (layout.binders[i].u64 == binder.u64) return i;
  return -1;
}

static void _layout_analyze_pattern(
  MatchCaptureLayout layout, Var pattern, unsigned long *definite,
  unsigned long *possible);

/* One definite/possible pair serves every child of a node: the per-pattern
   entry below clears both before it writes them. */
static void _layout_analyze_sequence(
  MatchCaptureLayout layout, List patterns, unsigned long *definite,
  unsigned long *possible) {
  foreach (Var pattern, patterns) {
    unsigned long part_definite, part_possible;
    _layout_analyze_pattern(layout, pattern, &part_definite, &part_possible);
    *definite |= part_definite;
    *possible |= part_possible;
  }
}

static void _layout_analyze_alternatives(
  MatchCaptureLayout layout, List patterns, unsigned long *definite,
  unsigned long *possible) {
  int first = 1;
  foreach (Var pattern, patterns) {
    unsigned long part_definite, part_possible;
    _layout_analyze_pattern(layout, pattern, &part_definite, &part_possible);
    *possible |= part_possible;
    *definite = first ? part_definite : *definite & part_definite;
    first = 0;
  }
}

static void _layout_analyze_pattern(
  MatchCaptureLayout layout, Var pattern, unsigned long *definite,
  unsigned long *possible) {
  *definite = 0;
  *possible = 0;
  if (_named_binder(pattern)) {
    int index = _layout_index(layout, pattern);
    assert(index >= 0);
    *definite = 1UL << index;
    *possible = *definite;
    return;
  }
  if (pattern is not <list> || pattern.is_nil()) return;

  List list = pattern;
  Var head = car(list);
  List args = cdr(list);
  if (head == <!quote>) return;
  if (head == <x2c-dyn>) {
    unsigned long ignored = 0;
    _layout_analyze_sequence(layout, args, &ignored, possible);
    return;
  }
  if (!head.is_match_op()) {
    _layout_analyze_sequence(layout, list, definite, possible);
    return;
  }
  if (head != <!set> && args && _named_binder(car(args))) {
    int index = _layout_index(layout, car(args));
    assert(index >= 0);
    *definite |= 1UL << index;
    *possible |= 1UL << index;
    args = cdr(args);
  }
  if (head == <!and>) {
    _layout_analyze_sequence(layout, args, definite, possible);
    return;
  }
  if (head == <!not>) {
    unsigned long ignored = 0;
    _layout_analyze_sequence(layout, args, &ignored, possible);
    *definite = 0;
    return;
  }
  if (head == <!or>) {
    unsigned long alt_definite = 0, alt_possible = 0;
    _layout_analyze_alternatives(layout, args, &alt_definite, &alt_possible);
    *definite |= alt_definite;
    *possible |= alt_possible;
    return;
  }
  if (head == <!set>) {
    if (args.len() == 2 && _named_binder(car(args)))
      _layout_analyze_sequence(layout, args, definite, possible);
    else _layout_analyze_alternatives(layout, args, definite, possible);
  }
}

static MatchCaptureLayout _capture_layout_analyze(
  Var pattern, Var *out_normalized) {
  MatchLayoutBuilder builder = {0};
  MachinePrepare status = MACHINE_PREPARED, const char *reason = "prepared";
  Var normalized = pattern;
  _layout_collect(&builder, pattern);
  if (builder.malformed_binder) {
    status = MACHINE_MALFORMED;
    reason = "binder-name";
  }
  else if (builder.leading_list_binder) {
    status = MACHINE_MALFORMED;
    reason = "leading-list-binder-in-guard";
  }
  else if (builder.past_capacity) {
    status = MACHINE_MALFORMED;
    reason = "binder-capacity";
  }
  else
    if (pattern is <list>) normalized = _normalize_pattern(pattern);

  if (status != MACHINE_PREPARED) builder.count = 0;
  if (out_normalized) *out_normalized = normalized;

  size_t bytes = sizeof(struct MatchCaptureLayout) +
                 sizeof(Atom) * builder.count;
  MatchCaptureLayout layout = Scope.calloc(1, bytes);
  layout.binders =
    (Atom *) ((char *) layout + sizeof(struct MatchCaptureLayout));
  layout.binder_count = builder.count;
  layout.status = status;
  layout.reason = reason;
  layout.normalized = normalized;
  if (builder.count)
    memcpy(layout.binders, builder.binders, sizeof(Atom) * builder.count);
  // a binder-free pattern has nothing to report as definite or possible
  if (status == MACHINE_PREPARED && builder.count)
    _layout_analyze_pattern(
      layout, pattern, &layout.definite, &layout.possible);
  return layout;
}

/** Analyzes one `Match` pattern into its canonical positional layout.
    Distinct named binders receive slots in lexical preorder. `!quote` is
    opaque; alternatives contribute possible binders, while only binders in
    every alternative are definite. The caller owns the returned layout,
    including when `status` is `MACHINE_MALFORMED`.
    Raises: `<alloc-fail>` while normalizing or allocating the layout.
*/
MatchCaptureLayout MatchCaptureLayout.analyze(Var pattern) =>
  _capture_layout_analyze(pattern, NULL);

/** Releases one canonical `Match` capture layout.
    A null layout is ignored; every alias is invalid afterward.
*/
void MatchCaptureLayout.free(MatchCaptureLayout layout) {
  if (layout) Scope.free(layout);
}

static List _capture_layout_list(
  MatchCaptureLayout layout, unsigned long included) {
  List result = NULL;
  for (int i = layout.binder_count - 1; i >= 0; i--)
    if (_capture_bit(included, i)) result = cons(layout.binders[i], result);
  return result;
}

/** Returns definite binders in canonical positional order.
    A null layout or no definite binders returns `nil`. The canonical result
    follows the module pool-chain lifetime above.
    Raises: `<alloc-fail>` while constructing the `List`.
*/
List MatchCaptureLayout.definite_list(MatchCaptureLayout layout) =>
  layout ? _capture_layout_list(layout, layout.definite) : NULL;

/** Returns possible binders in canonical positional order.
    A null layout or no possible binders returns `nil`. The canonical result
    follows the module pool-chain lifetime above.
    Raises: `<alloc-fail>` while constructing the `List`.
*/
List MatchCaptureLayout.possible_list(MatchCaptureLayout layout) =>
  layout ? _capture_layout_list(layout, layout.possible) : NULL;

/** Returns the canonical slot for `binder`, or -1 when it is absent.
    A null layout returns -1. Comparison uses exact `Atom` identity.
*/
int MatchCaptureLayout.index(MatchCaptureLayout layout, Atom binder) =>
  layout ? _layout_index(layout, binder) : -1;

/** Reports whether a committed capture slot is present.
    A null buffer or an index outside its capacity or `Match`'s binder limit
    returns false. Presence is independent of the captured `Var` value.
*/
int MatchCaptureBuffer.has(MatchCaptureBuffer *captures, int index) {
  if (!captures || index < 0 || index >= captures.capacity ||
      index >= MACHINE_BINDER_MAX)
    return 0;
  return _capture_bit(captures.present, index);
}

static int _find_fixed_anchor(List pat, Var *anchor, int *offset) {
  int width = 0;
  foreach (Var part, pat) {
    if (part.is_list_binder()) return 0;
    if ((part is not <list> && !part.is_binder()) ||
        (part is <list> && _is_list_literal(part))) {
      *anchor = part;
      *offset = width;
      return 1;
    }
    width++;
  }
  return 0;
}

static int _pattern_contains_binder(List pat, Var binder) {
  foreach (Var part, pat) {
    if (part == binder) return 1;
    if (part is <list>) {
      List nested = part;
      if (nested && car(nested) != <!quote> &&
          _pattern_contains_binder(nested, binder))
        return 1;
    }
  }
  return 0;
}

static inline Symbol _canonical_type_tag(Symbol tag) {
  if (tag == <varray>) return <array>;
  if (tag == <vmap>)   return <map>;
  return tag;
}

static int _capture_buffer_valid(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures) {
  if (!layout || !captures) return 0;
  if (captures.capacity < layout.binder_count) return 0;
  return !layout.binder_count || captures.values != NULL;
}

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

/** Matches `input` against `pat`, writing bindings on success.
    Returns 1 on a match and writes a reverse-slot-order association `List`, or
    returns 0 and leaves `out_bindings` unchanged. A successful binder-free
    match writes `nil`. A null output pointer returns 0.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing captures, or publishing bindings.
*/
int List.try_match(List input, Var pat, List *out_bindings) {
  if (!out_bindings) return 0;
  MatchPlan plan = _transient_plan(pat, "List.try_match");
  int result = plan.try_match(input, out_bindings);
  plan.free();
  return result == 1;
}

/** Returns bindings when `input` matches `pat`, or `nil` on a miss.
    A binder-free success returns the nonnull `%(())` sentinel
    with no associations. Binding order and failures follow `List.try_match`.
*/
List List.match(List input, Var pat) {
  List bindings;
  if (!input.try_match(pat, &bindings)) return NULL;
  return bindings ? bindings : %(());
}

static Var _replace(Var input, List bindings) {
  if (input.is_binder() && !(input == <*>) && !(input == <?>)) {
    Var val = bindings.assoc(input);
    if (val is void) return input;
    return val;
  }
  if (input is not <list>) return input;
  List lst = input;
  if (!lst) return input;
  Var head = car(lst);
  List tail = cdr(lst);
  if (head == <!quote>) return car(tail);
  // sequence binders splice their captured List into the result
  int splice = head.is_list_binder() && head != <*> && head != <?>;
  head = _replace(head, bindings);
  tail = _replace(tail, bindings);
  if (splice) return %(@head @tail);
  return %($head @tail);
}

/** Replaces named binders in `template` according to `bindings`.
    A sequence binder in list-head position splices its captured `List`;
    `!quote` removes itself and leaves its operand literal. Missing binders are
    retained. A null template returns `nil`, and null bindings return
    `template`
    unchanged. New structure follows the module pool-chain lifetime above.
    Raises: `<alloc-fail>` while constructing replacement `List`s.
*/
List List.replace(List template, List bindings) {
  if (!template) return NULL;
  if (!bindings) return template;
  return _replace(template, bindings);
}

static int _capture_lookup(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures, Var binder,
  Var *out) {
  int index = layout.index(binder);
  if (index < 0 || !_capture_bit(captures.present, index)) return 0;
  *out = captures.values[index];
  return 1;
}

static Var _capture_replace(
  Var input, MatchCaptureLayout layout, MatchCaptureBuffer *captures) {
  if (_named_binder(input)) {
    Var value;
    return _capture_lookup(layout, captures, input, &value) ? value : input;
  }
  if (input is not <list>) return input;
  List list = input;
  if (!list) return input;
  Var head = car(list);
  List tail = cdr(list);
  if (head == <!quote>) return car(tail);
  int splice = head.is_list_binder() && head != <*> && head != <?>;
  Var replaced_head = _capture_replace(head, layout, captures);
  List replaced_tail = _capture_replace(tail, layout, captures);
  if (splice) {
    List spliced = replaced_head is <list> ? replaced_head.list() : NULL;
    return %(@spliced @replaced_tail);
  }
  return %($replaced_head @replaced_tail);
}

static Var _apply_capture_template(
  MatchCaptureLayout layout, MatchCaptureBuffer *captures, Var template) {
  if (template is <list>) return _capture_replace(template, layout, captures);
  if (_named_binder(template)) {
    Var value = void;
    _capture_lookup(layout, captures, template, &value);
    return value;
  }
  return template;
}

/** Matches `input` and writes the instantiated `template` on success.
    The output may be any `Var`, including typed `nil` or a
    scalar. Returns 0 for
    a miss, malformed pattern, invalid output, or machine error and leaves
    `out` unchanged.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, materializing, or replacing.
*/
int List.try_match_replace(List input, Var pat, Var template, Var *out) {
  if (!out) return 0;
  MatchPlan plan = _transient_plan(pat, "List.try_match_replace");
  int result = plan.try_match_replace(input, template, out);
  plan.free();
  return result == 1;
}

/** Returns the `List` replacement when `input` matches `pat`.
    A miss returns `input` unchanged. A successful scalar replacement cannot
    inhabit the `List` result and returns `nil`. Matching and replacement
    failures
    follow `List.try_match_replace`.
*/
List List.match_replace(List input, Var pat, Var template) {
  Var result;
  if (!input.try_match_replace(pat, template, &result)) return input;
  return result is <list> ? result.list() : NULL;
}

/* One prepared walk owns a layout, machine, and capture buffer. */
typedef struct MatchWalk {
  MatchPlan plan;
  MachineView view;
  MatchCaptureBuffer *captures;
  MatchMachine m;
} *MatchWalk;

static int _walk_prepared(MatchWalk walk, Var input) =>
  _run_prepared_capture(walk.view, walk.m, input, walk.captures);

static List _walk_bindings(MatchWalk walk, Var input) =>
  cons(%(* $input), _capture_publish(walk.plan.layout, walk.captures));

/* A prepared walk stages every node through one positional stack buffer. */
macro Statement $match.walk_buffer(
  Expr $plan, Expr $machine, Name $walk) using $values, $captures => {
  Var $values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer $captures = { $values, 0, MACHINE_BINDER_MAX };
  struct MatchWalk $walk = {
    $plan, ($plan).program.view(), &$captures, $machine
  };
}

/* Every traversal descends car with include_empty=1 and cdr with
   include_empty=0 before trying the match at this node. */
static int _walk_all_prepared(
  MatchWalk walk, Var input, int include_empty, List *results) {
  if (input is <list>) {
    List lst = input;
    if (lst) {
      if (_walk_all_prepared(walk, car(lst), 1, results) < 0) return -1;
      if (_walk_all_prepared(walk, cdr(lst), 0, results) < 0) return -1;
    }
    else if (!include_empty) return 0;
  }
  int status = _walk_prepared(walk, input);
  if (status < 0) return -1;
  if (status == 1) *results = cons(_walk_bindings(walk, input), *results);
  return 0;
}

static int _walk_first_prepared(
  MatchWalk walk, Var input, int include_empty, Var *out_match,
  List *out_bindings) {
  if (input is <list>) {
    List lst = input;
    if (lst) {
      int found =
        _walk_first_prepared(walk, car(lst), 1, out_match, out_bindings);
      if (found) return found;
      found = _walk_first_prepared(walk, cdr(lst), 0, out_match, out_bindings);
      if (found) return found;
    }
    else if (!include_empty) return 0;
  }
  int status = _walk_prepared(walk, input);
  if (status != 1) return status;
  *out_match = input;
  *out_bindings = _capture_publish(walk.plan.layout, walk.captures);
  return 1;
}

static Var _walk_replace_prepared(
  MatchWalk walk, Var node, Var template, int include_empty, int *error) {
  if (node is <list>) {
    List lst = node;
    if (lst) {
      Var head = _walk_replace_prepared(walk, car(lst), template, 1, error);
      if (*error) return node;
      List tail = _walk_replace_prepared(walk, cdr(lst), template, 0, error);
      if (*error) return node;
      node = cons(head, tail);
    }
    else if (!include_empty) return node;
  }
  int status = _walk_prepared(walk, node);
  if (status < 0) {
    *error = 1;
    return node;
  }
  if (status == 0) return node;
  return _apply_capture_template(walk.plan.layout, walk.captures, template);
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
  List results = NULL;
  MatchPlan plan = _transient_plan(pat, "List.search");
  plan.search(input, &results);
  plan.free();
  return results;
}

/** Searches `input` for `pat`, writing the first match and bindings.
    The depth-first order is head, tail, then containing `List`, with the same
    explicit-`nil` rule as `List.search`. Returns 1 on success; otherwise
    returns
    0 and leaves both outputs unchanged. Either null output returns 0.
    Raises: the same causes as `List.search`.
*/
int List.try_search(List input, Var pat, Var *out_match, List *out_bindings) {
  if (!out_match || !out_bindings) return 0;
  MatchPlan plan = _transient_plan(pat, "List.try_search");
  int result = plan.try_search(input, out_match, out_bindings);
  plan.free();
  return result == 1;
}

/** Replaces every matching subtree in `input` from the leaves upward.
    Children are rewritten before their reconstructed containing `List` is
    tested. A miss, malformed pattern, or machine error returns `input`
    unchanged. New structure follows the module pool-chain lifetime
    above.
    Raises: `<size-limit>` for an ineligible pattern, or `<alloc-fail>` while
    preparing, traversing, or replacing.
*/
List List.search_replace(List input, Var pat, Var template) {
  List result = input;
  MatchPlan plan = _transient_plan(pat, "List.search_replace");
  plan.search_replace(input, template, &result);
  plan.free();
  return result;
}

// MatchPlan analysis and lowering

/* One recursive lowering pass compiles a normalized pattern to shared
   machine words.  Ordinary elements fuse against the segment cursor,
   star-free plain sublists descend inline through spare registers, and
   guards, quoted forms, starred or deep sublists keep call frames.
   Stars, ordered alternatives, and negation are branch/call templates
   over generic words; there is no STAR, OR, or NOT instruction. */

#define MATCH_SEGMENT_MAX 128
#define MATCH_INLINE_MAX   64

typedef struct MatchLower {
  MachineBuilder b;
  int *sites, site_count, site_capacity, depth;
} *MatchLower;

typedef struct MatchInlinePlan {
  int entries[64];  // MATCH_INLINE_MAX; typedefs hoist above the define
  int count, used;
} MatchInlinePlan;

static int MatchLower._fail(MatchLower l, const char *reason) {
  MachineBuilder b = l.b;
  if (b.status == MACHINE_PREPARED) {
    b.status = MACHINE_INELIGIBLE;
    b.reason = reason;
  }
  return -1;
}

static int MatchLower._stopped(MatchLower l) => l.b.status != MACHINE_PREPARED;

/* Emits the branch word with an unresolved target and records its patch
   site on the shared site stack.  This is the only place a failure site is
   created.  Every lowering path stops immediately on emission failure. */
static int MatchLower._fail_site(
  MatchLower l, int op, int a, int b, int c, int d) {
  int site = l.b.emit(op, a, b, c, d, -1);
  if (site < 0) return 0;
  if (l.site_count >= l.site_capacity) {
    int capacity = l.site_capacity ? l.site_capacity * 2 : 64;
    int *grown = Scope.realloc(l.sites, sizeof(int) * capacity);
    l.sites = grown;
    l.site_capacity = capacity;
  }
  l.sites[l.site_count++] = site;
  return 1;
}

/* Patch every site recorded since `base` to `target` and release
   them.  Block compilers leave the site stack at their entry base. */
static void MatchLower._patch_sites(MatchLower l, int base, int target) {
  for (int i = base; i < l.site_count; i++) l.b.set_target(l.sites[i], target);
  l.site_count = base;
}

/* Frame-depth fence: a block compiled here executes through one more
   call frame than its parent, so programs that could exceed the
   machine's frame capacity are rejected at preparation instead of
   erroring mid-execution. */
static int MatchLower._compile_child(MatchLower l, Var pattern) {
  if (l.depth + 1 >= MACHINE_FRAME_MAX - 1)
    return l._fail("frame-depth");
  l.depth++;
  int entry = l._compile_value(pattern);
  l.depth--;
  return entry;
}

static int MatchLower._compile_child_segment(MatchLower l, List pattern) {
  if (l.depth + 1 >= MACHINE_FRAME_MAX - 1)
    return l._fail("frame-depth");
  l.depth++;
  int entry = l._compile_segment(pattern);
  l.depth--;
  return entry;
}

/* Raw-bit comparison may replace general Var equality only where the
   two agree: Symbols are canonical identities, interned Lists have
   per-cell identity, and narrow integer immediates are value-encoded
   per family and width.  Wide boxes carry value semantics across
   distinct allocations, floating NaN is unequal to itself with equal
   bits, and a transient mutable String can be content-equal to a
   canonical String with different bits. */
static int _bits_unique(Var value) {
  switch (value.tag()) {
    case <symbol>: case <lsym>: case <list>:
    case <i8>: case <u8>: case <i16>: case <u16>:
    case <i32>: case <u32>: case <i48>: case <u48>:
      return 1;
  }
  return 0;
}

static int MatchLower._compile_literal(MatchLower l, Var pattern) {
  MachineBuilder b = l.b;
  int constant = b.constant(pattern);
  if (constant < 0) return -1;
  int mode = _bits_unique(pattern) ? MACHINE_COMPARE_BITS
                                   : MACHINE_COMPARE_EQUAL;
  int entry = b.length;
  int miss = b.emit(MW_EQ_VALUE_CONST, constant, 0, 0, mode, -1);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  int failure = b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  if (failure < 0) return -1;
  b.set_target(miss, failure);
  return entry;
}

static int MatchLower._finish_failure(MatchLower l, int base) {
  int failure = l.b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  if (failure < 0) return 0;
  l._patch_sites(base, failure);
  return 1;
}

static int MatchLower._finish(MatchLower l, int base) {
  l.b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  return l._finish_failure(base);
}

static int MatchLower._emit_call(MatchLower l, int child, int mode, int reg) {
  if (l.b.emit(MW_CALL, child, mode, reg, 0, 0) < 0) return 0;
  return l._fail_site(MW_BR_FAIL, 0, 0, 0, 0);
}

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

/* Inline test of the current value for an atom pattern inside a guard
   or segment template: literals compare, atom binders bind or compare
   through the journal in slot order, and the anonymous ? matches
   without emitting a word.  Failure sites are recorded for the
   enclosing block to patch. */
static int MatchLower._emit_leaf_value(MatchLower l, Var pattern) {
  if (pattern.is_atom_binder()) return l._emit_binder(pattern);
  MachineBuilder b = l.b;
  int constant = b.constant(pattern);
  if (constant < 0) return 0;
  int mode = _bits_unique(pattern) ? MACHINE_COMPARE_BITS
                                   : MACHINE_COMPARE_EQUAL;
  return l._fail_site(MW_EQ_VALUE_CONST, constant, 0, 0, mode);
}

static int MatchLower._collect_guard_args(
  MatchLower l, List args, Var *elements, int *children) {
  int count = 0;
  foreach (Var part, args) {
    if (count >= MATCH_SEGMENT_MAX) return l._fail("guard-width");
    elements[count] = part;
    if (part is not <list>) children[count++] = -1;
    else {
      children[count] = l._compile_child(part);
      if (children[count++] < 0) return -1;
    }
  }
  return count;
}

static int MatchLower._compile_call_sequence(MatchLower l, List args) {
  MachineBuilder b = l.b;
  Var elements[MATCH_SEGMENT_MAX];
  int children[MATCH_SEGMENT_MAX];
  int count = l._collect_guard_args(args, elements, children);
  if (count < 0) return -1;

  int entry = b.length, base = l.site_count;
  for (int i = 0; i < count; i++) {
    if (children[i] < 0) {
      if (!l._emit_leaf_value(elements[i])) return -1;
      continue;
    }
    if (!l._emit_call(children[i], MACHINE_CALL_CURRENT, 0)) return -1;
  }
  return l._finish(base) ? entry : -1;
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

/* Ordered alternatives are static call/branch/return templates: every
   failed arm returns through its paired undo/order call-entry mark,
   and the first successful arm returns immediately as the local cut. */
static int MatchLower._compile_choice(MatchLower l, List args) {
  MachineBuilder b = l.b;
  Var elements[MATCH_SEGMENT_MAX];
  int children[MATCH_SEGMENT_MAX];
  int count = l._collect_guard_args(args, elements, children);
  if (count < 0) return -1;

  int entry = b.length, base = l.site_count;
  for (int i = 0; i < count; i++) {
    l._patch_sites(base, b.length);
    if (children[i] < 0) {
      if (!l._emit_leaf_value(elements[i])) return -1;
    }
    else
      if (!l._emit_call(children[i], MACHINE_CALL_CURRENT, 0)) return -1;

    if (b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0) < 0) return -1;
  }
  int failure = b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0);
  if (failure < 0) return -1;
  l._patch_sites(base, failure);
  return entry;
}

/* Negation uses one frame-local mark and rolls the journal back on
   both inverted outcomes, so no child binding can leak. */
static int MatchLower._compile_not(MatchLower l, List args) {
  MachineBuilder b = l.b;
  Var elements[MATCH_SEGMENT_MAX];
  int children[MATCH_SEGMENT_MAX];
  int count = l._collect_guard_args(args, elements, children);
  if (count < 0) return -1;

  int entry = b.length, base = l.site_count;
  b.emit(MW_MARK, 0, 0, 0, 0, 0);
  int successes[MATCH_SEGMENT_MAX], success_count = 0;
  for (int i = 0; i < count; i++) {
    l._patch_sites(base, b.length);
    if (children[i] < 0) {
      if (!l._emit_leaf_value(elements[i])) return -1;
    }
    else
      if (!l._emit_call(children[i], MACHINE_CALL_CURRENT, 0)) return -1;

    successes[success_count++] = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
    if (successes[success_count - 1] < 0) return -1;
  }

  int all_failed = b.length;
  l._patch_sites(base, all_failed);
  b.emit(MW_ROLLBACK, 0, MACHINE_ROLLBACK_RESTORE, 0, 0, 0);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);

  int rejected = b.length;
  b.patch(successes, success_count, rejected);
  b.emit(MW_ROLLBACK, 0, MACHINE_ROLLBACK_RESTORE, 0, 0, 0);
  if (b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0) < 0) return -1;
  return entry;
}

/* The current !is shapes. Unknown shapes fail at execution, and the
   tag test canonicalizes varray/vmap to the public tags before freezing the
   constant. */
static int MatchLower._compile_is(MatchLower l, List args) {
  MachineBuilder b = l.b;
  int entry = b.length, base = l.site_count, kind = -1;
  Var (kind_arg, type_tag) = args;
  if (args == %(var binder))       kind = MACHINE_KIND_ATOM_BINDER;
  else if (args == %(list binder)) kind = MACHINE_KIND_LIST_BINDER;
  else if (args == %(binder))      kind = MACHINE_KIND_BINDER;
  else if (args == %(op))          kind = MACHINE_KIND_MATCH_OP;
  if (kind >= 0) {
    if (!l._fail_site(MW_MATCH_KIND, 0, kind, 0, 0)) return -1;
  }
  else if (args == %(atom)) {
    int constant = b.constant(<list>);
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
  else if (args && kind_arg == <type> && cdr(args) && !args.cddr()) {
    Symbol tag = type_tag is <symbol> ? type_tag.symbol() : 0;
    tag = _canonical_type_tag(tag);
    if (!tag) {
      if (b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0) < 0) return -1;
      return entry;
    }
    int constant = b.constant(tag);
    if (constant < 0 || !l._fail_site(MW_TAG, constant, 0, 0, 0)) return -1;
  }
  else {
    if (b.emit(MW_RET_FAILURE, 0, 0, 0, 0, 0) < 0) return -1;
    return entry;
  }
  return l._finish(base) ? entry : -1;
}

static int MatchLower._compile_guard_core(MatchLower l, Var op, List args) {
  if (op == <!or>) return l._compile_choice(args);
  if (op == <!not>) return l._compile_not(args);
  if (op == <!is>) return l._compile_is(args);
  if (op == <!set>) {
    if (args && cdr(args) && !args.cddr() && car(args).is_atom_binder()) {
      Var (binder, test) = args;
      if (test is not <list>) return l._compile_bind_and_leaf(binder, test);
      int child = l._compile_child(test);
      if (child < 0) return -1;
      return l._compile_bind_and(binder, child);
    }
    return l._compile_choice(args);
  }
  if (op == <!and>) return l._compile_call_sequence(args);
  // op == <!quote>: current runtime compares only one quoted operand.
  if (!args || cdr(args)) return l._fail("quote-arity");
  return l._compile_literal(car(args));
}

/* A final star consumes the remaining input: a fresh binder shares the
   native suffix directly, a repeated binder keeps production's shallow
   List identity rule and memoizes a proven span as its suffix VALUE. */
static int MatchLower._lower_final_star(MatchLower l, int slot) {
  MachineBuilder b = l.b;
  int entry = b.length;
  if (slot < 0) {
    if (b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0) < 0) return -1;
    return entry;
  }

  int valid = b.emit(MW_SLOT_VALID, slot, 0, 0, 0, -1);
  b.emit(MW_CURSOR_VALUE, 0, 1, 0, 0, 0);
  b.emit(MW_SLOT_SET_VALUE, slot, 0, 0, 0, 0);
  int fresh = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  if (valid < 0 || fresh < 0) return -1;

  int existing = b.length;
  int is_span = b.emit(MW_SLOT_IS_SPAN, slot, 0, 0, 0, -1);
  b.emit(MW_CURSOR_VALUE, 0, 0, 0, 0, 0);
  if (!l._fail_site(MW_SLOT_EQ_VALUE, slot, 0, 0, 0)) return -1;
  int value_done = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
  if (is_span < 0 || value_done < 0) return -1;

  int compare_span = b.length;
  if (!l._fail_site(MW_SLOT_EQ_FINAL_IDENTITY, slot, 0, 1, 0)) return -1;
  b.emit(MW_CURSOR_VALUE, 0, 1, 0, 0, 0);
  b.emit(MW_SLOT_SET_VALUE, slot, 1, 0, 0, 0);

  int success = b.length;
  if (b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0) < 0) return -1;
  b.set_target(valid, existing);
  b.set_target(is_span, compare_span);
  b.set_target(fresh, success);
  b.set_target(value_done, success);
  return entry;
}

/* An interior star enumerates shortest-first splits.  An anchored star
   pairs monotonic split/probe cursors through one fused SCAN; an
   unanchored star advances one optional split per retry.  A unique
   unreferenced binder defers its span until the tail succeeds, and a
   repeated binder compares the candidate range in place. */
static int MatchLower._lower_search_star(
  MatchLower l, int slot, int delayed, int tail_entry, int anchored,
  Var anchor, int anchor_offset) {
  MachineBuilder b = l.b;
  int anchor_constant = anchored ? b.constant(anchor) : -1;
  if (anchored && anchor_constant < 0) return -1;
  int mode = anchored && !_bits_unique(anchor) ? MACHINE_COMPARE_EQUAL
                                               : MACHINE_COMPARE_BITS;
  b.emit(MW_MARK, 0, 0, 0, 0, 0);
  b.emit(MW_MOVE, 1, 0, 0, 0, 0);
  if (anchored) {
    b.emit(MW_MOVE, 2, 1, 0, 0, 0);
    b.emit(MW_OFFSET, 2, anchor_offset, 0, 0, 0);
  }
  else
    b.emit(MW_SET_ACTIVE, 0, 1, 0, 0, 0);

  int loop = b.length;
  int emitted = anchored
    ? l._fail_site(MW_SCAN, 1, 2, anchor_constant, mode)
    : l._fail_site(MW_REQUIRE_ACTIVE, 0, 0, 0, 0);
  if (!emitted) return -1;

  int valid = -1;
  if (slot >= 0) valid = b.emit(MW_SLOT_VALID, slot, 0, 0, 0, -1);
  if (slot >= 0 && !delayed) b.emit(MW_SLOT_SET_SPAN, slot, 0, 1, 0, 0);

  b.emit(MW_CALL, tail_entry, MACHINE_CALL_CURSOR, 1, 0, 0);
  int fresh_failed = b.emit(MW_BR_FAIL, 0, 0, 0, 0, -1);
  if (fresh_failed < 0) return -1;
  if (slot >= 0 && delayed) b.emit(MW_SLOT_SET_SPAN, slot, 0, 1, 0, 0);
  b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);

  int mismatch = -1, existing_failed = -1;
  if (slot >= 0) {
    int compare = b.length;
    mismatch = b.emit(MW_SLOT_EQ_PREFIX, slot, 0, 1, 0, -1);
    b.emit(MW_CALL, tail_entry, MACHINE_CALL_CURSOR, 1, 0, 0);
    existing_failed = b.emit(MW_BR_FAIL, 0, 0, 0, 0, -1);
    if (mismatch < 0 || existing_failed < 0) return -1;
    b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
    b.set_target(valid, compare);
  }

  int retry = b.length;
  b.set_target(mismatch, retry);
  b.set_target(fresh_failed, retry);
  b.set_target(existing_failed, retry);
  b.emit(MW_ROLLBACK, 0, MACHINE_ROLLBACK_RETRY, 0, 0, 0);
  if (anchored) {
    b.emit(MW_ADVANCE, 1, 0, 0, 0, 0);
    b.emit(MW_ADVANCE, 2, 0, 0, 0, 0);
  }
  else
    b.emit(MW_ADVANCE_OPTIONAL, 1, 0, 0, 0, 0);

  if (b.emit(MW_JUMP, 0, 0, 0, 0, loop) < 0) return -1;
  return l._stopped() ? -1 : 0;
}

/* A star-free plain nested segment may execute in the enclosing frame
   through the bank's next cursor register: stars are the only other
   consumers of registers one and two and always run in their own
   frame; guards and quoted forms keep call frames, and literal lists
   keep the canonical-identity path. */
static int _inline_descend_ok(List child, int reg) {
  if (reg + 1 >= MACHINE_CURSOR_REGS) return 0;
  if (!child) return 0;
  if (car(child).is_match_op()) return 0;
  if (_is_list_literal(child)) return 0;
  foreach (Var part, child) if (part.is_list_binder()) return 0;
  return 1;
}

/* Pre-compile every framed child block reachable through inline
   descends, in traversal order, so the linear emission below consumes
   the entries in the same order. */
static int MatchLower._plan_inline_segment(
  MatchLower l, List pattern, int reg, MatchInlinePlan *plan) {
  foreach (Var part, pattern) {
    if (part is not <list>) continue;
    List child = part;
    if (_inline_descend_ok(child, reg)) {
      if (!l._plan_inline_segment(child, reg + 1, plan)) return 0;
      continue;
    }
    if (plan.count >= MATCH_INLINE_MAX)
      return l._fail("segment-width") + 1;
    plan.entries[plan.count] = l._compile_child(part);
    if (plan.entries[plan.count++] < 0) return 0;
  }
  return 1;
}

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
  int mode = _bits_unique(part) ? MACHINE_COMPARE_BITS : MACHINE_COMPARE_EQUAL;
  return l._fail_site(MW_EQ_HEAD_CONST, constant, reg, 0, mode);
}

static int MatchLower._emit_inline_segment(
  MatchLower l, List pattern, int reg, MatchInlinePlan *plan) {
  MachineBuilder b = l.b;
  foreach (Var part, pattern) {
    if (part is not <list>) {
      if (!l._emit_head_leaf(part, reg)) return -1;
      continue;
    }
    List child = part;
    if (_inline_descend_ok(child, reg)) {
      if (!l._fail_site(MW_DESCEND, 0, reg, reg + 1, 0)) return -1;
      if (l._emit_inline_segment(child, reg + 1, plan) < 0) return -1;
      if (b.emit(MW_ADVANCE, reg, 0, 0, 0, 0) < 0) return -1;
      continue;
    }
    assert(plan.used < plan.count);
    int child_entry = plan.entries[plan.used++];
    if (!l._fail_site(MW_NONNIL, reg, 0, 0, 0)) return -1;
    if (!l._emit_call(child_entry, MACHINE_CALL_HEAD, reg)) return -1;
    if (b.emit(MW_ADVANCE, reg, 0, 0, 0, 0) < 0) return -1;
  }
  if (!l._fail_site(MW_NIL, reg, 0, 0, 0)) return -1;
  return 0;
}

static int MatchLower._compile_segment(MatchLower l, List pattern) {
  MachineBuilder b = l.b;
  Var elements[MATCH_SEGMENT_MAX];
  int children[MATCH_SEGMENT_MAX];
  MatchInlinePlan plan;
  plan.count = 0;
  plan.used = 0;
  int child_count = 0, List at = pattern;
  while (at && !car(at).is_list_binder()) {
    if (child_count >= MATCH_SEGMENT_MAX)
      return l._fail("segment-width");
    Var part = car(at);
    elements[child_count] = part;
    /* Atom elements execute inline against the cursor head; star-free
       plain sublists descend inline through the next register;
       guards, quoted forms, literal lists, and starred or deep
       sublists keep a call frame with an independent register bank. */
    if (part is not <list>) children[child_count++] = -1;
    else if (_inline_descend_ok(part, 0)) {
      if (!l._plan_inline_segment(part, 1, &plan)) return -1;
      children[child_count++] = -2;
    }
    else {
      children[child_count] = l._compile_child(part);
      if (children[child_count++] < 0) return -1;
    }
    at = cdr(at);
  }

  Var star_binder;
  List tail = NULL;
  int star_slot = -1, delayed = 0, tail_entry = -1, anchored = 0;
  Var anchor = void;
  int anchor_offset = 0;
  if (at) {
    star_binder = car(at);
    tail = cdr(at);
    if (star_binder != <*>) {
      star_slot = b.binder(star_binder);
      if (star_slot < 0) return -1;
      delayed = tail && !_pattern_contains_binder(tail, star_binder);
    }
    if (tail) {
      tail_entry = l._compile_child_segment(tail);
      if (tail_entry < 0) return -1;
      anchored = _find_fixed_anchor(tail, &anchor, &anchor_offset);
    }
  }

  int entry = b.length, base = l.site_count;
  if (!l._fail_site(MW_INPUT_LIST, 0, 0, 0, 0)) return -1;
  for (int i = 0; i < child_count; i++) {
    if (children[i] == -1) {
      if (!l._emit_head_leaf(elements[i], 0)) return -1;
      continue;
    }
    if (children[i] == -2) {
      if (!l._fail_site(MW_DESCEND, 0, 0, 1, 0)) return -1;
      if (l._emit_inline_segment(elements[i], 1, &plan) < 0) return -1;
      if (b.emit(MW_ADVANCE, 0, 0, 0, 0, 0) < 0) return -1;
      continue;
    }
    if (!l._fail_site(MW_NONNIL, 0, 0, 0, 0)) return -1;
    if (!l._emit_call(children[i], MACHINE_CALL_HEAD, 0)) return -1;
    if (b.emit(MW_ADVANCE, 0, 0, 0, 0, 0) < 0) return -1;
  }

  if (!at) {
    if (!l._fail_site(MW_NIL, 0, 0, 0, 0)) return -1;
    b.emit(MW_RET_SUCCESS, 0, 0, 0, 0, 0);
  }
  else if (!tail) {
    if (l._lower_final_star(star_slot) < 0) return -1;
  }
  else
    if (l._lower_search_star(
      star_slot, delayed, tail_entry, anchored,
      anchor, anchor_offset) < 0)
      return -1;

  return l._finish_failure(base) ? entry : -1;
}

/* A binder-free literal list compares by canonical identity first and
   falls back to the elementwise segment, mirroring the recursive
   matcher's interned-list fast path without collapsing boxed-equal
   elements into a bit comparison. */
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

static int MatchLower._compile_value(MatchLower l, Var pattern) {
  if (pattern.is_atom_binder()) return l._compile_binder(pattern);
  if (pattern is not <list>) return l._compile_literal(pattern);
  List list = pattern;
  if (list && car(list).is_match_op())
    return l._compile_guard_core(car(list), cdr(list));
  if (list && _is_list_literal(list)) return l._compile_literal_list(list);
  return l._compile_segment(list);
}

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

/* Prepare one pattern: reject the approved malformed form on the raw
   tree, normalize like the public entry points, lower, and freeze an
   exact-sized immutable program in the caller's scope. */
/** Compiles `pattern` into a reusable immutable `MatchPlan`.
    The caller owns the returned plan in the active `Scope`. Preparation
    reports
    `MACHINE_PREPARED`, `MACHINE_MALFORMED`, or `MACHINE_INELIGIBLE` in the
    plan rather than raising for those outcomes; only a prepared plan has a
    program. `reason` is a borrowed static category string. The plan borrows
    pattern constants, which must outlive it.
    Raises: `<alloc-fail>` while analyzing, lowering, or freezing.
*/
MatchPlan MatchPlan.prepare(Var pattern) {
  MatchPlan plan = Scope.malloc(sizeof(struct MatchPlan));
  plan.program = NULL;
  Var normalized;
  plan.layout = _capture_layout_analyze(pattern, &normalized);
  if (plan.layout.status != MACHINE_PREPARED) {
    plan.status = plan.layout.status;
    plan.reason = plan.layout.reason;
    return plan;
  }
  pattern = normalized;
  struct MatchLower storage;
  MatchLower lower = &storage;
  lower.b = MachineBuilder.new();
  with lower.b {
    lower.sites = NULL;
    lower.site_count = 0;
    lower.site_capacity = 0;
    lower.depth = 1;
    for (int i = 0; i < plan.layout.binder_count; i++) {
      int slot = _.binder(plan.layout.binders[i]);
      if (slot != i) break;
    }
    _.root = _.status == MACHINE_PREPARED
           ? lower._compile_value(pattern) : -1;
    if (_.root < 0 && _.status == MACHINE_PREPARED) {
      _.status = MACHINE_INELIGIBLE;
      _.reason = "lowering";
    }
    plan.status = _.status;
    plan.reason = _.reason;
    if (plan.status == MACHINE_PREPARED) plan.program = _.freeze();
    if (lower.sites) Scope.free(lower.sites);
    _.free();
  }
  return plan;
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

/* Run one prepared execution and commit positional values only after the
   machine and every lazy-span materialization have succeeded. */
static int _run_prepared_capture(
  MachineView view, MatchMachine m, Var input, MatchCaptureBuffer *captures) {
  if (!captures || captures.capacity < view.binder_count ||
      (view.binder_count && !captures.values))
    return -1;
  m.begin(view, input);
  m.run();
  int result = -1;
  if (m.status == <ok>) {
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
    if (m.status == <ok>) {
      captures.present = present;
      for (int i = 0; i < view.binder_count; i++)
        if (_capture_bit(present, i)) captures.values[i] = values[i];
      result = 1;
    }
  }
  else if (m.status == <fail>) result = 0;
  m.finish();
  return result;
}

/* Publication reads committed positional state, never speculative matcher
   state. */
static int MatchPlan._run(
  MatchPlan plan, MatchMachine m, Var input, List *out) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = { values, 0, MACHINE_BINDER_MAX };
  int result = _run_prepared_capture(plan.program.view(), m, input, &captures);
  if (result == 1) *out = _capture_publish(plan.layout, &captures);
  return result;
}

static int MatchPlan._capture(
  MatchPlan plan, Var input, MatchCaptureBuffer *captures,
  MachineStats *stats) {
  $match.machine(machine, stats);
  int result = _run_prepared_capture(
    plan.program.view(), machine, input, captures);
  machine.dispose();
  return result;
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
  MatchPlan plan, Var input, MatchCaptureBuffer *captures,
  MachineStats *stats) {
  if (!_plan_prepared(plan, "MatchPlan.execute_capture") ||
      !_capture_buffer_valid(plan.layout, captures))
    return -1;
  return plan._capture(input, captures, stats);
}

/** Executes a prepared `List` match into caller-owned positional storage.
    This is `MatchPlan.execute_capture` without statistics and has the same
    results, atomicity, and failures.
*/
int MatchPlan.try_capture(
  MatchPlan plan, List input, MatchCaptureBuffer *captures) =>
    plan.execute_capture(input, captures, NULL);

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
  MatchPlan plan, Var input, List *out_bindings, MachineStats *stats) {
  if (!_plan_prepared(plan, "MatchPlan.execute") || !out_bindings) return -1;
  $match.machine(machine, stats);
  List bindings, int result = plan._run(machine, input, &bindings);
  machine.dispose();
  if (result == 1) *out_bindings = bindings;
  return result;
}

/** Executes prepared `plan` against `input`, writing bindings on success.
    This is `MatchPlan.execute` without statistics and has the same status,
    output atomicity, ordering, and failures.
*/
int MatchPlan.try_match(MatchPlan plan, List input, List *out_bindings) =>
  plan.execute(input, out_bindings, NULL);

static int MatchPlan._first(
  MatchPlan plan, List input, Var *out_match, List *out_bindings) {
  $match.machine(machine, NULL);
  $match.walk_buffer(plan, machine, walk);
  Var matched;
  List bindings;
  int result = _walk_first_prepared(&walk, input, 1, &matched, &bindings);
  machine.dispose();
  if (result == 1) {
    *out_match = matched;
    *out_bindings = bindings;
  }
  return result;
}

/** Searches `input` with `plan`, writing the first match and bindings.
    Traversal is depth-first head, tail, then containing `List`. Returns 1 on a
    match, 0 on a miss, and -1 for an unusable plan, invalid outputs, or a
    machine error. Unless it returns 1, both outputs remain unchanged.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    materializing or publishing bindings.
*/
int MatchPlan.try_search(
  MatchPlan plan, List input, Var *out_match, List *out_bindings) {
  if (!_plan_prepared(plan, "MatchPlan.try_search") || !out_match ||
      !out_bindings)
    return -1;
  return plan._first(input, out_match, out_bindings);
}

static int MatchPlan._all(MatchPlan plan, List input, List *out_results) {
  $match.machine(machine, NULL);
  $match.walk_buffer(plan, machine, walk);
  List results = NULL;
  int status = _walk_all_prepared(&walk, input, 1, &results);
  machine.dispose();
  if (status < 0) return -1;
  *out_results = results;
  return 1;
}

/** Writes all matches of `plan` within `input` to `out_results`.
    Each result has the shape documented by `List.search` and the completed
    `List` is in reverse visitation order. Returns 1 after a complete
    traversal,
    including when it writes `nil` for no matches; returns -1 and leaves the
    output unchanged for an unusable plan, null output, or machine error.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    constructing results.
*/
int MatchPlan.search(MatchPlan plan, List input, List *out_results) {
  if (!_plan_prepared(plan, "MatchPlan.search") || !out_results) return -1;
  return plan._all(input, out_results);
}

static int MatchPlan._replace(
  MatchPlan plan, List input, Var template, Var *out) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = { values, 0, MACHINE_BINDER_MAX };
  int result = plan._capture(input, &captures, NULL);
  if (result != 1) return result;
  *out = _apply_capture_template(plan.layout, &captures, template);
  return 1;
}

/** Executes `plan` and writes the instantiated `template` on success.
    Returns 1 after writing any `Var` result, 0 on a miss, and -1 for an
    unusable
    plan, null output, or machine error. Non-success leaves `out` unchanged.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    materializing captures or replacing.
*/
int MatchPlan.try_match_replace(
  MatchPlan plan, List input, Var template, Var *out) {
  if (!_plan_prepared(plan, "MatchPlan.try_match_replace") || !out) return -1;
  return plan._replace(input, template, out);
}

static int MatchPlan._replace_all(
  MatchPlan plan, List input, Var template, List *out) {
  $match.machine(machine, NULL);
  $match.walk_buffer(plan, machine, walk);
  int error = 0;
  Var result = _walk_replace_prepared(&walk, input, template, 1, &error);
  machine.dispose();
  if (error) return -1;
  *out = result;
  return 1;
}

/** Replaces every match of `plan` from the leaves upward.
    Returns 1 and writes the completed `List` even when nothing matched.
    Returns
    -1 and leaves `out` unchanged for an unusable plan, null output, or machine
    error. Children are replaced before their containing `List` is tested.
    Raises: `<size-limit>` for an ineligible plan, or `<alloc-fail>` while
    traversing or replacing.
*/
int MatchPlan.search_replace(
  MatchPlan plan, List input, Var template, List *out) {
  if (!_plan_prepared(plan, "MatchPlan.search_replace") || !out) return -1;
  return plan._replace_all(input, template, out);
}

// pattern admissibility for compiler-owned sites

/* A site retains its prepared program for the life of the process, so it may
   only bind a pattern whose values outlive it. Symbols and narrow immediates
   have value lifetime. Canonical Lists and long Atoms are admitted by
   identity. A String is admitted only when `String.is_permanent` proves the
   outermost canonical pool owns it. Wide boxes, pointers, references, and
   transient Strings are never admitted; those patterns prepare a plan per
   call instead. */
static int _pattern_admissible(Var value, int depth) {
  if (depth >= 128) return 0;
  Symbol kind = value.kind();
  switch (kind) {
    case <symbol>: return 1;
    case <pointer>: case <reference>: return 0;
    case <object>: {
      if (value is <lsym>) return 1;
      if (value is <string>) return String.is_permanent(value.str());
      if (value is not <list>) return 0;
      // kind and tag prove the raw payload is a List cell
      foreach (Var part, (List) value.pointer())
        if (!_pattern_admissible(part, depth + 1)) return 0;
      return 1;
    }
  }
  return value is not <long> && value is not <ulong> &&
         value is not <llong> && value is not <ullong> &&
         value is not <ldouble>;
}

/* Prepares one plan for a single call. Every runtime pattern route uses it;
   the caller frees the plan once its results are materialized. */
static MatchPlan _transient_plan(Var pattern, const char *owner) {
  MatchPlan plan = MatchPlan.prepare(pattern);
  if (plan.status == MACHINE_INELIGIBLE) {
    const char *reason = plan.reason;
    plan.free();
    _raise_ineligible(reason, owner);
  }
  return plan;
}

// compiler-owned static source sites
static Scope match_capture_site_scope;
static Block match_capture_sites;

static pthread_mutex_t match_site_mutex =
  (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;

static void _site_lock(void) {
  if (pthread_mutex_lock(&match_site_mutex)) {
    fprintf(stderr, "Match: could not lock source site\n");
    abort();
  }
}

static void _site_unlock(void) {
  if (pthread_mutex_unlock(&match_site_mutex)) {
    fprintf(stderr, "Match: could not unlock source site\n");
    abort();
  }
}

static void _capture_sites_shutdown(void) {
  if (!match_capture_site_scope) return;
  MatchCaptureSite **sites = (void *) match_capture_sites != NULL
                           ? match_capture_sites.bytes : NULL;
  for (size_t i = 0; i < match_capture_sites.length; i++) {
    MatchCaptureSite *site = sites[i];
    if (!site || !site.plan) continue;
    site.plan.free();
    site.plan = NULL;
  }
  if ((void *) match_capture_sites != NULL) match_capture_sites.free();
  Scope.destroy(match_capture_site_scope);
  match_capture_site_scope = NULL;
}

static pthread_once_t match_shutdown_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;

static void _shutdown(void) {
  _capture_sites_shutdown();
}

static void _register_shutdown_once(void) {
  Scope.shutdown_hook(_shutdown);
}

/** Registers process-wide `Match` cleanup exactly once.
    Repeated calls have no effect. Failure of the native once primitive writes
    a diagnostic and aborts the process.
    Raises: `<alloc-fail>` or `<size-limit>` while registering the shutdown
    hook.
*/
void x2c_match_initialize(void) {
  if (pthread_once(&match_shutdown_once, _register_shutdown_once)) {
    fprintf(stderr, "Match: could not register shutdown\n");
    abort();
  }
}

static void _capture_sites_initialize(void) {
  if (match_capture_site_scope) return;
  match_capture_site_scope = Scope.new_named("Match source-site plans");
  $scope(&match_capture_site_scope) {
    match_capture_sites = Block.new(sizeof(MatchCaptureSite *));
  }
  x2c_match_initialize();
}

static void _capture_site_prepare(MatchCaptureSite *site, Var pattern) {
  if (!_pattern_admissible(pattern, 0)) return;
  _capture_sites_initialize();
  MatchPlan plan = NULL;
  $scope(&match_capture_site_scope) {
    plan = MatchPlan.prepare(pattern);
    match_capture_sites.push(&site);
  }
  __atomic_store_n(&site.plan, plan, __ATOMIC_RELEASE);
}

/* Prepares one site once, under the lock that also guards the site
   registry. Every later call sees the published plan and skips this. */
static MatchPlan _capture_site_publish(
  MatchCaptureSite *site, Var pattern) {
  _site_lock();
  // preparation allocates, and an allocation failure never returns here
  defer _site_unlock();
  if (!site.plan) _capture_site_prepare(site, pattern);
  return site.plan;
}
