/*  match-recursive.x -- optional reference matcher

    Copyright (c) 2026 Gary William Flake

    This direct matcher is the readable reference for differential tests.
    The prelude's public `Match` operations run the compiled machine in
    match.x; include this module only when an independent recursive oracle
    is useful.
*/

#pragma once
#include "x2c.x"

#pragma private

typedef struct RecursiveMatchState {
  MatchCaptureLayout layout;
  Var values[MACHINE_BINDER_MAX];
  List span_begin[MACHINE_BINDER_MAX], span_end[MACHINE_BINDER_MAX];
  int span_length[MACHINE_BINDER_MAX];
  unsigned long present, spans;
} *RecursiveMatchState;

static int _match(RecursiveMatchState state, Var input, Var pattern);

static int _bind(RecursiveMatchState state, Var binder, Var value) {
  if (binder == <?> || binder == <*>) return 1;
  int index = state.layout.index(binder);
  if (index < 0) return 0;
  unsigned long bit = 1UL << index;
  if (state.present & bit)
    return !(state.spans & bit) && state.values[index] == value;
  state.values[index] = value;
  state.present |= bit;
  return 1;
}

static int _bind_span(
  RecursiveMatchState r, Var binder, List input, List end, int length) {
  if (binder == <*>) return 1;
  int index = r.layout.index(binder);
  if (index < 0) return 0;
  unsigned long bit = 1UL << index;
  if (!(r.present & bit)) {
    r.span_begin[index] = input;
    r.span_end[index] = end;
    r.span_length[index] = length;
    r.present |= bit;
    r.spans |= bit;
    return 1;
  }

  List expected;
  if (r.spans & bit) {
    if (r.span_length[index] != length) return 0;
    expected = r.span_begin[index];
  }
  else {
    if (r.values[index] is not <list>) return 0;
    expected = r.values[index];
  }
  for (int i = 0; i < length; i++) {
    if (!input || !expected || !(input.car() == expected.car())) return 0;
    input = input.cdr();
    expected = expected.cdr();
  }
  return r.spans & bit ? expected == r.span_end[index] : !expected;
}

static int _bind_final(
  RecursiveMatchState state, Var binder, List input) {
  if (binder == <*>) return 1;
  int index = state.layout.index(binder);
  if (index < 0) return 0;
  unsigned long bit = 1UL << index;
  if (!(state.present & bit)) return _bind(state, binder, input);
  if (!(state.spans & bit))
    return state.values[index] is <list> &&
           state.values[index].list() == input;

  List expected = state.span_begin[index], candidate = input, int length = 0;
  while (length < state.span_length[index] &&
         expected != state.span_end[index] && candidate) {
    if (expected.car().u64 != candidate.car().u64) return 0;
    expected = expected.cdr();
    candidate = candidate.cdr();
    length++;
  }
  if (length != state.span_length[index] ||
      expected != state.span_end[index] || candidate)
    return 0;
  state.values[index] = input;
  state.spans &= ~bit;
  return 1;
}

/* Each star candidate snapshots every capture so a failed suffix cannot leak
   bindings into the next attempt. */
static int _star_candidate(
  RecursiveMatchState state, List input, List rest, int length, Var binder,
  List pattern_tail) {
  struct RecursiveMatchState snapshot = *state;
  int matched = _bind_span(state, binder, input, rest, length) &&
                _match(state, rest, pattern_tail);
  if (!matched) *state = snapshot;
  return matched;
}

/* Prefix lengths run shortest first, giving each `*` binder the leftmost
   shortest capture that permits the remaining pattern to match. */
static int _star(
  RecursiveMatchState state, List input, List pattern) {
  Var binder = pattern.car();
  List pattern_tail = pattern.cdr();
  if (!pattern_tail) return _bind_final(state, binder, input);

  List rest = input;
  for (int length = 0;; length++) {
    if (_star_candidate(
      state, input, rest, length, binder, pattern_tail))
      return 1;
    if (!rest) return 0;
    rest = rest.cdr();
  }
}

static int _all(
  RecursiveMatchState state, Var input, List patterns) {
  foreach(Var pattern, patterns)
    if (!_match(state, input, pattern)) return 0;
  return 1;
}

/* Alternatives run in source order and restore captures after each miss. */
static int _any(
  RecursiveMatchState state, Var input, List patterns) {
  foreach(Var pattern, patterns) {
    struct RecursiveMatchState snapshot = *state;
    if (_match(state, input, pattern)) return 1;
    *state = snapshot;
  }
  return 0;
}

/* Negated probes never publish captures. */
static int _none(
  RecursiveMatchState state, Var input, List patterns) {
  foreach(Var pattern, patterns) {
    struct RecursiveMatchState snapshot = *state;
    int matched = _match(state, input, pattern);
    *state = snapshot;
    if (matched) return 0;
  }
  return 1;
}

static Symbol _type_tag(Symbol tag) {
  if (tag == <varray>) return <array>;
  if (tag == <vmap>) return <map>;
  return tag;
}

static int _is(Var input, List patterns) {
  if (patterns == %(var binder))  return input.is_atom_binder();
  if (patterns == %(list binder)) return input.is_list_binder();
  if (patterns == %(binder))      return input.is_binder();
  if (patterns == %(op))          return input.is_match_op();
  if (patterns == %(atom))        return input is not <list>;
  Var (kind, type) = patterns;
  if (patterns && kind == <type> && patterns.cdr() &&
      !patterns.cddr()) {
    Symbol tag = type is <symbol> ? type.symbol() : 0;
    return input is _type_tag(tag);
  }
  return 0;
}

static int _match(
  RecursiveMatchState state, Var input, Var pattern) {
  if (pattern.is_atom_binder()) return _bind(state, pattern, input);
  if (input is not <list> && pattern is not <list>) return input == pattern;
  if (pattern is not <list>) return 0;

  List list_pattern = pattern;
  Var head = list_pattern.car();
  List tail = list_pattern.cdr();
  if (head is <symbol>) {
    switch (head.symbol()) {
      case <!is>:    return _is(input, tail);
      case <!or>:    return _any(state, input, tail);
      case <!and>:   return _all(state, input, tail);
      case <!not>:   return _none(state, input, tail);
      case <!set>:
        if (tail.len() == 2 && tail.car().is_atom_binder())
          return _all(state, input, tail);
        return _any(state, input, tail);
      case <!quote>: return tail.car() == input;
    }
  }
  if (input is not <list>) return 0;
  List input_list = input;
  if (!list_pattern) return !input_list;
  if (head.is_list_binder())
    return _star(state, input_list, list_pattern);
  if (!input_list) return 0;
  if (!_match(state, input_list.car(), head)) return 0;
  return _match(state, input_list.cdr(), tail);
}

static List _bindings(RecursiveMatchState state) {
  List result = NULL;
  for (int i = 0; i < state.layout.binder_count; i++) {
    unsigned long bit = 1UL << i;
    if (!(state.present & bit)) continue;
    Var value = state.values[i];
    if (state.spans & bit) {
      int length = state.span_length[i];
      value = length ? state.span_begin[i][:length].var()
                     : ((List) NULL).var();
    }
    result = cons(%(${state.layout.binders[i]} $value), result);
  }
  return result;
}

static int _try_capture(
  MatchCaptureLayout layout, Var input, MatchCaptureBuffer *captures) {
  if (!layout || !captures || layout.status == MACHINE_MALFORMED ||
      captures.capacity < layout.binder_count ||
      (layout.binder_count && !captures.values))
    return 0;
  /* Speculation stays local until the complete match succeeds, so a miss
     cannot alter the caller's value array or presence bits. */
  struct RecursiveMatchState state = { .layout = layout };
  if (!_match(&state, input, layout.normalized)) return 0;
  for (int i = 0; i < layout.binder_count; i++) {
    unsigned long bit = 1UL << i;
    if (!(state.present & bit)) continue;
    if (state.spans & bit) {
      int length = state.span_length[i];
      captures.values[i] = length ? state.span_begin[i][:length].var()
                                  : ((List) NULL).var();
    }
    else captures.values[i] = state.values[i];
  }
  captures.present = state.present;
  return 1;
}

static int _try_value(Var input, Var pattern, List *out_bindings) {
  if (!out_bindings) return 0;
  MatchCaptureLayout layout = MatchCaptureLayout.analyze(pattern);
  if (layout.status == MACHINE_MALFORMED) {
    layout.free();
    return 0;
  }
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = {
    values, 0, MACHINE_BINDER_MAX
  };
  int matched = _try_capture(layout, input, &captures);
  if (matched) {
    struct RecursiveMatchState state = {
      .layout = layout, .present = captures.present
    };
    for (int i = 0; i < layout.binder_count; i++) state.values[i] = values[i];
    *out_bindings = _bindings(&state);
  }
  layout.free();
  return matched;
}

static List _search(
  Var input, Var pattern, List results, int include_empty) {
  if (input is <list>) {
    List list = input;
    if (list) {
      results = _search(list.car(), pattern, results, 1);
      results = _search(list.cdr(), pattern, results, 0);
    }
    else if (!include_empty) return results;
  }
  List bindings;
  if (_try_value(input, pattern, &bindings))
    results = cons(cons(%(* $input), bindings), results);
  return results;
}

/* Both searches visit car, cdr, then the node. Prepending every hit makes the
   all-results form reverse visitation order, while the first form returns the
   first visited hit. `include_empty` admits root and explicitly stored nil but
   suppresses a proper List's implicit terminal cdr. */
static int _first(
  Var input, Var pattern, int include_empty, Var *out_match,
  List *out_bindings) {
  if (input is <list>) {
    List list = input;
    if (list) {
      if (_first(list.car(), pattern, 1, out_match, out_bindings))
        return 1;
      if (_first(list.cdr(), pattern, 0, out_match, out_bindings))
        return 1;
    }
    else if (!include_empty) return 0;
  }
  if (!_try_value(input, pattern, out_bindings)) return 0;
  *out_match = input;
  return 1;
}

static Var _replace_all(
  Var input, Var pattern, Var template, int include_empty) {
  if (input is <list>) {
    List list = input;
    if (list) {
      Var head = _replace_all(list.car(), pattern, template, 1);
      List tail = _replace_all(list.cdr(), pattern, template, 0);
      input = cons(head, tail);
    }
    else if (!include_empty) return input;
  }
  List bindings;
  if (!_try_value(input, pattern, &bindings)) return input;
  if (template is <list>) return template.list().replace(bindings);
  if (template.is_binder()) return bindings.assoc(template);
  return template;
}

#pragma public

/** Matches `input` against `layout` with the recursive reference engine.
    Returns 1 and publishes positional captures on success. A null or
    malformed layout, an invalid or undersized buffer, and a mismatch return
    0 without changing the caller-owned buffer or value array. On success,
    `present` identifies the written slots; the call does not retain the
    layout or the capture buffer. Star-capture `List`s are canonical and follow
    their owning `List` pool's lifetime, possibly an ancestor of the current
    pool.

    Raises: `<alloc-fail>` or `<size-limit>` while materializing captures.
*/
int match_recursive_try_capture(
  MatchCaptureLayout layout, Var input, MatchCaptureBuffer *captures) =>
    _try_capture(layout, input, captures);

/** Matches any `input` against `pattern` with the recursive reference engine.
    Returns 1 and writes a canonical association `List` of named bindings on
    success, including `nil` when no named binder is present. The binding
    `List`
    and star-capture `List`s follow their owning `List` pool's lifetime,
    possibly
    an ancestor of the current pool. A malformed pattern, mismatch,
    or null output pointer returns 0 and leaves the output unchanged.

    Raises: `<alloc-fail>` or `<size-limit>` while analyzing or binding.
*/
int match_recursive_try_value(Var input, Var pattern, List *out_bindings) =>
  _try_value(input, pattern, out_bindings);

/** Matches `input` against `pattern` with the recursive reference engine.
    Returns 1 and writes a canonical association `List` of named bindings on
    success, including `nil` when no named binder is present. The binding
    `List`
    and star-capture `List`s follow their owning `List` pool's lifetime,
    possibly
    an ancestor of the current pool. A malformed pattern, mismatch,
    or null output pointer returns 0 and leaves the output unchanged.

    Raises: `<alloc-fail>` or `<size-limit>` while analyzing or binding.
*/
int match_recursive_try_match(List input, Var pattern, List *out_bindings) =>
  match_recursive_try_value(input, pattern, out_bindings);

/** Matches `input` and writes the instantiated `template` on success.
    Returns 0 for a malformed pattern, mismatch, or null output pointer and
    leaves the output unchanged. A successful output may be any `Var`,
    including
    typed `nil`. Any constructed output `List` is canonical and follows its
    owning `List` pool's lifetime, possibly an ancestor of the current pool.

    Raises: `<alloc-fail>` or `<size-limit>` while matching or replacing.
*/
int match_recursive_try_match_replace(
  List input, Var pattern, Var template, Var *out) {
  if (!out) return 0;
  List bindings;
  if (!match_recursive_try_match(input, pattern, &bindings)) return 0;
  if (template is <list>) *out = template.list().replace(bindings);
  else if (template.is_binder()) *out = bindings.assoc(template);
  else *out = template;
  return 1;
}

/** Returns every recursively matching node and its named bindings.
    Traversal visits car, then cdr, then the node. Each hit is prepended, so
    the returned order reverses that visitation. The result, its records, and
    star-capture `List`s are canonical and follow their owning `List` pool's
    lifetime, possibly an ancestor of the current pool. Each record maps `<*>`
    to the matched node.
    Explicit `nil` nodes are visited, but a proper `List`'s implicit terminal
    cdr
    is not. Returns `nil` when the pattern is malformed or no node matches.

    Raises: `<alloc-fail>` or `<size-limit>` while searching or binding.
*/
List match_recursive_search(List input, Var pattern) =>
  _search(input, pattern, NULL, 1);

/** Visits car, then cdr, then the node and writes the first matching node.
    The binding `List` and star-capture `List`s are canonical and follow their
    owning `List` pool's lifetime, possibly an ancestor of the current pool;
    bindings are `nil` when no named binder is present. Returns 0 for a
    malformed pattern, mismatch, or null output pointer and leaves both outputs
    unchanged.
    Explicit `nil` nodes are visited, but a proper `List`'s implicit terminal
    cdr
    is not.

    Raises: `<alloc-fail>` or `<size-limit>` while searching or binding.
*/
int match_recursive_try_search(
  List input, Var pattern, Var *out_match, List *out_bindings) =>
    out_match && out_bindings &&
         _first(input, pattern, 1, out_match, out_bindings);

/** Replaces every recursively matching node and returns the resulting `List`.
    Traversal rewrites car, then cdr, then matches the node. The result is
    canonical; constructed cells follow their owning `List` pool's lifetime,
    possibly an ancestor of the current pool. Explicit `nil` nodes are
    visited, but a proper `List`'s implicit terminal cdr is not.

    Raises: `<alloc-fail>` or `<size-limit>` while searching or replacing.
*/
List match_recursive_search_replace(List input, Var pattern, Var template) =>
  _replace_all(input, pattern, template, 1);
