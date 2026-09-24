/*  diff.x -- line differences between two texts

    Copyright (c) 2026 Gary William Flake

    `Diff.lines` finds a shortest edit script between two texts with the
    Myers algorithm after trimming the lines the texts share at both ends.
    Each step keeps only the frontier it reached, so the search costs the
    square of the edit distance and nothing more. An edit distance past
    `_LIMIT` is reported as one deletion of the old middle and one insertion
    of the new, which is what a reader wants of two unrelated texts anyway.
*/

#pragma once
#include "x2c.x"

/** The receiverless owner of the difference operations. */
typedef enum Diff {
  DIFF_NAMESPACE
} Diff;

meta List Diff.lines(String old, String new);
meta String Diff.unified(String old, String new, String old_name,
                         String new_name);

#pragma private

static const int _LIMIT = 2000;
static const int _CONTEXT = 3;

typedef struct {
  Array old, new;
  List edits;
} _Diff;

static void _emit(_Diff *d, Symbol kind, String line) {
  d.edits = cons(%($kind $line), d.edits);
}

static int _same(_Diff *d, int i, int j) =>
  d.old[i].string() == d.new[j].string();

/* Myers' greedy search over old[lo..old_hi) and new[lo..new_hi). Returns
   the edit count, or -1 past the limit, after emitting the edits. The
   frontier of step `s` has `2s + 1` entries indexed by `k + s`, so the
   frontiers of all steps fit one buffer with step `s` starting at `s * s`. */
static int _myers(_Diff *d, int lo, int old_hi, int new_hi) {
  int n = old_hi - lo, m = new_hi - lo;
  int max = n + m < _LIMIT ? n + m : _LIMIT, found = -1;
  int *trace = Scope.calloc((max + 1) * (max + 1), sizeof(int));
  defer Scope.free(trace);
  for (int step = 0; step <= max && found < 0; step++) {
    int *frontier = trace + step * step, *previous = frontier - 2 * step + 1;
    for (int k = -step; k <= step; k += 2) {
      int x = 0;
      if (step > 0) {
        int left = k > -step ? previous[k - 1 + step - 1] : -1;
        int right = k < step ? previous[k + 1 + step - 1] : -1;
        x = k == -step || (k != step && left < right) ? right : left + 1;
      }
      int y = x - k;
      while (x < n && y < m && _same(d, lo + x, lo + y)) x++, y++;
      frontier[k + step] = x;
      if (x >= n && y >= m) {
        found = step;
        break;
      }
    }
  }
  if (found < 0) return -1;
  /* Walk the frontiers back from the end to recover the path. */
  List path = NULL;
  int x = n, y = m;
  for (int step = found; step > 0; step--) {
    int *previous = trace + (step - 1) * (step - 1), k = x - y;
    int left = k > -step ? previous[k - 1 + step - 1] : -1;
    int right = k < step ? previous[k + 1 + step - 1] : -1;
    int inserted = k == -step || (k != step && left < right);
    int prev_k = inserted ? k + 1 : k - 1;
    int prev_x = inserted ? right : left, prev_y = prev_x - prev_k;
    int mid_x = inserted ? prev_x : prev_x + 1;
    int mid_y = inserted ? prev_y + 1 : prev_y;
    while (x > mid_x && y > mid_y) {
      path = cons(%(same ${x - 1} ${y - 1}), path);
      x--, y--;
    }
    path = cons(inserted ? %(insert $prev_x $prev_y)
                         : %(delete $prev_x $prev_y), path);
    x = prev_x, y = prev_y;
  }
  while (x > 0 && y > 0) {
    path = cons(%(same ${x - 1} ${y - 1}), path);
    x--, y--;
  }
  foreach (List step, path) {
    (Symbol kind, int i, int j) = step;
    _emit(d, kind, kind == <insert> ? d.new[lo + j] : d.old[lo + i]);
  }
  return found;
}

static void _replace(_Diff *d, int lo, int old_hi, int new_hi) {
  for (int i = lo; i < old_hi; i++) _emit(d, <delete>, d.old[i]);
  for (int j = lo; j < new_hi; j++) _emit(d, <insert>, d.new[j]);
}

static Symbol _kind(Array edits, int at) => edits[at].list().car();

static void _hunk(Buffer out, List lines, int old_start, int old_count,
                  int new_start, int new_count) {
  out.printf("@@ -%d,%d +%d,%d @@\n", old_count ? old_start + 1 : old_start,
             old_count, new_count ? new_start + 1 : new_start, new_count);
  foreach (String line, lines) out.write(line);
}

/** Returns the line edits that turn `old` into `new`: a `List` of
    `(same line)`, `(delete line)`, and `(insert line)` forms in order, with
    each line's ending removed. Two equal texts give only `same` forms.
    Past 2,000 edits the differing middle is one run of deletions followed
    by one run of insertions.
*/
List Diff.lines(String old, String new) {
  _Diff d = {old.split_lines(0).array(), new.split_lines(0).array()};
  int lo = 0, old_hi = d.old.len(), new_hi = d.new.len();
  while (lo < old_hi && lo < new_hi && _same(&d, lo, lo)) {
    _emit(&d, <same>, d.old[lo]);
    lo++;
  }
  int tail = 0;
  while (old_hi > lo && new_hi > lo && _same(&d, old_hi - 1, new_hi - 1)) {
    old_hi--, new_hi--, tail++;
  }
  if (_myers(&d, lo, old_hi, new_hi) < 0) _replace(&d, lo, old_hi, new_hi);
  for (int i = old_hi; i < old_hi + tail; i++) _emit(&d, <same>, d.old[i]);
  return d.edits.reverse();
}

/** Returns the unified difference between `old` and `new`, as `diff -u`
    prints it with `old_name` and `new_name` in the header and three lines
    of context, or NULL when the texts are equal line for line.
*/
String Diff.unified(String old, String new, String old_name,
                    String new_name) {
  Array edits = $auto(Diff.lines(old, new).array());
  Buffer out = $auto(Buffer.new(0));
  int count = edits.len(), at = 0, old_line = 0, new_line = 0;
  while (at < count) {
    if (_kind(edits, at) == <same>) {
      at++, old_line++, new_line++;
      continue;
    }
    if (!out.len()) out.printf("--- %s\n+++ %s\n", old_name, new_name);
    int start = at > _CONTEXT ? at - _CONTEXT : 0, lead = at - start;
    int old_start = old_line - lead, new_start = new_line - lead;
    int end = at, quiet = 0;
    while (end < count && quiet <= 2 * _CONTEXT)
      quiet = _kind(edits, end++) == <same> ? quiet + 1 : 0;
    if (quiet > _CONTEXT) end -= quiet - _CONTEXT;
    List lines = NULL;
    int old_count = 0, new_count = 0;
    for (int i = start; i < end; i++) {
      (Symbol kind, String text) = edits[i].list();
      char mark = kind == <same> ? ' ' : kind == <delete> ? '-' : '+';
      lines = cons(%"$mark$text\n", lines);
      if (kind != <insert>) old_count++;
      if (kind != <delete>) new_count++;
    }
    _hunk(out, lines.reverse(), old_start, old_count, new_start, new_count);
    old_line = old_start + old_count;
    new_line = new_start + new_count;
    at = end;
  }
  return out;
}
