/*  diff.x -- line differences between two texts

    Copyright (c) 2026 Gary William Flake

    Diff owns line differences: a shortest edit script between two texts,
    found with the Myers algorithm after trimming the lines both share at
    each end, and its unified spelling. Each search step keeps only its
    frontier, so the cost is the square of the edit distance; past `_LIMIT`
    edits the middle becomes one deletion run and one insertion run.
*/

#pragma once
#include "x2c.x"

/** The receiverless owner of the difference operations. */
typedef enum Diff {
  DIFF_NAMESPACE
} Diff;

#pragma private

// line edits

static const int _LIMIT = 2000;

/* The lines of both texts and the edits so far, newest first. The texts
   differ only in old[lo..lo + n) and new[lo..lo + m). */
typedef struct Script {
  Array old, new, List edits, int lo, n, m;
} Script;

/** Returns the line edits that turn `old` into `new`: a `List` of
    `(same line)`, `(delete line)`, and `(insert line)` forms in order, with
    each line's ending removed. Two equal texts give only `same` forms.
    Past 2,000 edits the differing middle is one run of deletions followed
    by one run of insertions.
*/
meta native List Diff.lines(String old, String new) {
  Array old_lines = $auto(old.split_lines(0).array());
  Array new_lines = $auto(new.split_lines(0).array());
  Script s = {old_lines, new_lines};
  s.trim();
  if (s.myers() < 0) s.replace();
  for (int i = s.lo + s.n; i < s.old.len(); i++) s.emit(<same>, s.old[i]);
  return s.edits.reverse();
}

/* Emits the lines both texts start with and sets the middle to the lines
   before those both texts end with. */
static void Script.trim(Script *s) {
  int lo = 0, old_hi = s.old.len(), new_hi = s.new.len();
  for (; lo < old_hi && lo < new_hi && s.same(lo, lo); lo++)
    s.emit(<same>, s.old[lo]);
  while (old_hi > lo && new_hi > lo && s.same(old_hi - 1, new_hi - 1))
    old_hi--, new_hi--;
  s.lo = lo, s.n = old_hi - lo, s.m = new_hi - lo;
}

/* Past `_LIMIT`, the middle becomes one run of deletions and one run of
   insertions. */
static void Script.replace(Script *s) {
  for (int i = s.lo; i < s.lo + s.n; i++) s.emit(<delete>, s.old[i]);
  for (int j = s.lo; j < s.lo + s.m; j++) s.emit(<insert>, s.new[j]);
}

static void Script.emit(Script *s, Symbol kind, String line) =>
  s.edits = cons(%($kind $line), s.edits);

static int Script.same(Script *s, int i, int j) =>
  s.old[i].string() == s.new[j].string();

/* frontier search

   Step `s` of the search holds, for each diagonal `k = x - y` in -s..s,
   the furthest old index `x` that `s` edits reach on it. A walk back
   through the frontiers from the end recovers the edits. */

/* The frontiers of every step in one buffer: step `s` starts at `s * s`
   and has `2s + 1` entries, indexed by `k + s`. */
typedef int *Trace;

/* Myers' greedy search over the middle. Returns the edit count after
   emitting the edits, or -1 past `_LIMIT`. */
static int Script.myers(Script *s) {
  int max = s.n + s.m < _LIMIT ? s.n + s.m : _LIMIT;
  Trace trace = Scope.calloc((max + 1) * (max + 1), sizeof(int));
  defer Scope.free(trace);
  int found = s.forward(trace, max);
  if (found < 0) return -1;
  foreach (List step, trace.path(found, s.n, s.m)) {
    (Symbol kind, int i, int j) = step;
    s.emit(kind, kind == <insert> ? s.new[s.lo + j] : s.old[s.lo + i]);
  }
  return found;
}

/* Fills the frontier of each step up to `max` and returns the first step
   whose path reaches the end of both middles, or -1. */
static int Script.forward(Script *s, Trace trace, int max) {
  for (int step = 0; step <= max; step++)
    for (int k = -step; k <= step; k += 2) {
      int x = s.snake(trace.entry(step, k), k);
      trace[step * step + k + step] = x;
      if (x >= s.n && x - k >= s.m) return step;
    }
  return -1;
}

/* Follows diagonal `k` from old index `x` while the lines agree and
   returns the old index where it stops. */
static int Script.snake(Script *s, int x, int k) {
  int y = x - k;
  while (x < s.n && y < s.m && s.same(s.lo + x, s.lo + y)) x++, y++;
  return x;
}

/* Where diagonal `k` starts at `step`: the end of diagonal `k + 1` after
   an insertion, or one past the end of diagonal `k - 1` after a
   deletion. */
static int Trace.entry(Trace trace, int step, int k) {
  if (!step) return 0;
  int left = trace.at(step - 1, k - 1), right = trace.at(step - 1, k + 1);
  return _inserted(step, k, left, right) ? right : left + 1;
}

/* The furthest old index on diagonal `k` at `step`, or -1 off its
   frontier. */
static int Trace.at(Trace trace, int step, int k) =>
  k < -step || k > step ? -1 : trace[step * step + k + step];

/* True when `step` reaches diagonal `k` by an insertion from diagonal
   `k + 1`, which reached old index `right` a step earlier, and false for a
   deletion from diagonal `k - 1`, which reached `left`. */
static int _inserted(int step, int k, int left, int right) =>
  k == -step || (k != step && left < right);

/* Walks back from the end of both middles and returns the path as
   `(same i j)`, `(delete i j)`, and `(insert i j)` steps in order, with
   indexes into the middles. */
static List Trace.path(Trace trace, int found, int n, int m) {
  List path = NULL;
  int x = n, y = m;
  for (int step = found; step > 0; step--) {
    int k = x - y;
    int left = trace.at(step - 1, k - 1), right = trace.at(step - 1, k + 1);
    int inserted = _inserted(step, k, left, right);
    int prev_k = inserted ? k + 1 : k - 1, prev_x = inserted ? right : left;
    int prev_y = prev_x - prev_k;
    int mid_x = inserted ? prev_x : prev_x + 1;
    int mid_y = inserted ? prev_y + 1 : prev_y;
    path = _diagonal(path, x, y, mid_x, mid_y);
    path = cons(
      inserted ? %(insert $prev_x $prev_y) : %(delete $prev_x $prev_y),
      path);
    x = prev_x, y = prev_y;
  }
  return _diagonal(path, x, y, 0, 0);
}

/* Prepends to `path` the `same` steps that lead diagonally from
   (`to_x`, `to_y`) to (`x`, `y`). */
static List _diagonal(List path, int x, int y, int to_x, int to_y) {
  for (; x > to_x && y > to_y; x--, y--)
    path = cons(%(same ${x - 1} ${y - 1}), path);
  return path;
}

// unified differences

static const int _CONTEXT = 3;

/* One hunk: its end in the edits, where it starts in each text, how many
   lines of each text it covers, and its marked lines, newest first. */
typedef struct Hunk {
  int end, old_start, old_count, new_start, new_count, List lines;
} Hunk;

/** Returns the unified difference between `old` and `new`, as `diff -u`
    prints it with `old_name` and `new_name` in the header and three lines
    of context, or NULL when the texts are equal line for line.
*/
meta native String Diff.unified(
  String old, String new, String old_name, String new_name) {
  Array edits = $auto(Diff.lines(old, new).array());
  Buffer out = $auto(Buffer.new(0));
  int count = edits.len(), at = 0, old_line = 0, new_line = 0;
  while (at < count) {
    if (_kind(edits, at) == <same>) {
      at++, old_line++, new_line++;
      continue;
    }
    if (!out.len()) out.printf("--- %s\n+++ %s\n", old_name, new_name);
    Hunk h = _hunk(edits, at, old_line, new_line);
    h.write(out);
    at = h.end;
    old_line = h.old_start + h.old_count;
    new_line = h.new_start + h.new_count;
  }
  return out;
}

static Symbol _kind(Array edits, int at) => edits[at].list().car();

/* The hunk around the change at `at`, which `old_line` lines of the old
   text and `new_line` of the new precede. */
static Hunk _hunk(Array edits, int at, int old_line, int new_line) {
  int start = at > _CONTEXT ? at - _CONTEXT : 0, lead = at - start;
  Hunk h = {_hunk_end(edits, at), old_line - lead, 0, new_line - lead, 0};
  for (int i = start; i < h.end; i++) {
    (Symbol kind, String text) = edits[i].list();
    h.lines = cons(%"${_mark(kind)}$text\n", h.lines);
    if (kind != <insert>) h.old_count++;
    if (kind != <delete>) h.new_count++;
  }
  return h;
}

/* A hunk runs on while its changes are at most `2 * _CONTEXT` unchanged
   lines apart, and keeps `_CONTEXT` unchanged lines after its last
   change. */
static int _hunk_end(Array edits, int at) {
  int count = edits.len(), end = at, quiet = 0;
  while (end < count && quiet <= 2 * _CONTEXT)
    quiet = _kind(edits, end++) == <same> ? quiet + 1 : 0;
  if (quiet > _CONTEXT) end -= quiet - _CONTEXT;
  return end;
}

static char _mark(Symbol kind) {
  switch (kind) {
    case <same>:   return ' ';
    case <delete>: return '-';
  }
  return '+';
}

/* An empty side of a hunk starts at the line before it, as `diff -u`
   prints it. */
static void Hunk.write(Hunk *h, Buffer out) {
  out.printf(
    "@@ -%d,%d +%d,%d @@\n", h.old_count ? h.old_start + 1 : h.old_start,
    h.old_count, h.new_count ? h.new_start + 1 : h.new_start, h.new_count);
  foreach (String line, h.lines.reverse()) out.write(line);
}
