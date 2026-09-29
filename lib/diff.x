/*  diff.x -- line differences between two texts

    Copyright (c) 2026 Gary William Flake

    `Diff.lines` finds a shortest edit script between two texts with the
    Myers algorithm after trimming the lines the texts share at both ends.
    Each step keeps only the frontier it reached, so the search costs the
    square of the edit distance. An edit distance past `_LIMIT` becomes one
    deletion of the old middle and one insertion of the new, which is what a
    reader wants of two unrelated texts.
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
typedef struct _Diff {
  Array old, new, List edits, int lo, n, m;
} _Diff;

/** Returns the line edits that turn `old` into `new`: a `List` of
    `(same line)`, `(delete line)`, and `(insert line)` forms in order, with
    each line's ending removed. Two equal texts give only `same` forms.
    Past 2,000 edits the differing middle is one run of deletions followed
    by one run of insertions.
*/
meta native List Diff.lines(String old, String new) {
  _Diff d = {old.split_lines(0).array(), new.split_lines(0).array()};
  d.trim();
  if (d.myers() < 0) d.replace();
  for (int i = d.lo + d.n; i < d.old.len(); i++) d.emit(<same>, d.old[i]);
  return d.edits.reverse();
}

/* Emits the lines both texts start with and sets the middle to the lines
   before those both texts end with. */
static void _Diff.trim(_Diff *d) {
  int lo = 0, old_hi = d.old.len(), new_hi = d.new.len();
  for (; lo < old_hi && lo < new_hi && d.same(lo, lo); lo++)
    d.emit(<same>, d.old[lo]);
  while (old_hi > lo && new_hi > lo && d.same(old_hi - 1, new_hi - 1))
    old_hi--, new_hi--;
  d.lo = lo, d.n = old_hi - lo, d.m = new_hi - lo;
}

/* Past `_LIMIT`, the middle becomes one run of deletions and one run of
   insertions. */
static void _Diff.replace(_Diff *d) {
  for (int i = d.lo; i < d.lo + d.n; i++) d.emit(<delete>, d.old[i]);
  for (int j = d.lo; j < d.lo + d.m; j++) d.emit(<insert>, d.new[j]);
}

static void _Diff.emit(_Diff *d, Symbol kind, String line) =>
  d.edits = cons(%($kind $line), d.edits);

static int _Diff.same(_Diff *d, int i, int j) =>
  d.old[i].string() == d.new[j].string();

/* frontier search

   Step `s` of the search holds, for each diagonal `k = x - y` in -s..s,
   the furthest old index `x` that `s` edits reach on it. A walk back
   through the frontiers from the end recovers the edits. */

/* The frontiers of every step in one buffer: step `s` starts at `s * s`
   and has `2s + 1` entries, indexed by `k + s`. */
typedef int *_Trace;

/* Myers' greedy search over the middle. Returns the edit count after
   emitting the edits, or -1 past `_LIMIT`. */
static int _Diff.myers(_Diff *d) {
  int max = d.n + d.m < _LIMIT ? d.n + d.m : _LIMIT;
  _Trace trace = Scope.calloc((max + 1) * (max + 1), sizeof(int));
  defer Scope.free(trace);
  int found = d.forward(trace, max);
  if (found < 0) return -1;
  foreach (List step, trace.path(found, d.n, d.m)) {
    (Symbol kind, int i, int j) = step;
    d.emit(kind, kind == <insert> ? d.new[d.lo + j] : d.old[d.lo + i]);
  }
  return found;
}

/* Fills the frontier of each step up to `max` and returns the first step
   whose path reaches the end of both middles, or -1. */
static int _Diff.forward(_Diff *d, _Trace trace, int max) {
  for (int step = 0; step <= max; step++)
    for (int k = -step; k <= step; k += 2) {
      int x = d.snake(trace.entry(step, k), k);
      trace[step * step + k + step] = x;
      if (x >= d.n && x - k >= d.m) return step;
    }
  return -1;
}

/* Follows diagonal `k` from old index `x` while the lines agree and
   returns the old index where it stops. */
static int _Diff.snake(_Diff *d, int x, int k) {
  int y = x - k;
  while (x < d.n && y < d.m && d.same(d.lo + x, d.lo + y)) x++, y++;
  return x;
}

/* Where diagonal `k` starts at `step`: the end of diagonal `k + 1` after
   an insertion, or one past the end of diagonal `k - 1` after a
   deletion. */
static int _Trace.entry(_Trace trace, int step, int k) {
  if (!step) return 0;
  int left = trace.at(step - 1, k - 1), right = trace.at(step - 1, k + 1);
  return _inserted(step, k, left, right) ? right : left + 1;
}

/* The furthest old index on diagonal `k` at `step`, or -1 off its
   frontier. */
static int _Trace.at(_Trace trace, int step, int k) =>
  k < -step || k > step ? -1 : trace[step * step + k + step];

/* True when `step` reaches diagonal `k` by an insertion from diagonal
   `k + 1`, which reached old index `right` a step earlier, and false for a
   deletion from diagonal `k - 1`, which reached `left`. */
static int _inserted(int step, int k, int left, int right) =>
  k == -step || (k != step && left < right);

/* Walks back from the end of both middles and returns the path as
   `(same i j)`, `(delete i j)`, and `(insert i j)` steps in order, with
   indexes into the middles. */
static List _Trace.path(_Trace trace, int found, int n, int m) {
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
typedef struct _Hunk {
  int end, old_start, old_count, new_start, new_count, List lines;
} _Hunk;

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
    _Hunk h = _hunk(edits, at, old_line, new_line);
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
static _Hunk _hunk(Array edits, int at, int old_line, int new_line) {
  int start = at > _CONTEXT ? at - _CONTEXT : 0, lead = at - start;
  _Hunk h = {_hunk_end(edits, at), old_line - lead, 0, new_line - lead, 0};
  for (int i = start; i < h.end; i++) h.add(edits[i]);
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

static void _Hunk.add(_Hunk *h, List edit) {
  (Symbol kind, String text) = edit;
  h.lines = cons(%"${_mark(kind)}$text\n", h.lines);
  if (kind != <insert>) h.old_count++;
  if (kind != <delete>) h.new_count++;
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
static void _Hunk.write(_Hunk *h, Buffer out) {
  out.printf(
    "@@ -%d,%d +%d,%d @@\n", h.old_count ? h.old_start + 1 : h.old_start,
    h.old_count, h.new_count ? h.new_start + 1 : h.new_start, h.new_count);
  foreach (String line, h.lines.reverse()) out.write(line);
}
