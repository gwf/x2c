/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 *
 * Adapted from the contributions recorded in ../../benchmarks.json.
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "typed-array.x"

class Rows {
  ArrayDbl input, output;
  int first, last, transpose;
  Thread worker;
} *;

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 100;
  ArrayDbl u = ArrayDbl.new(), v = ArrayDbl.new(), scratch = ArrayDbl.new();
  for (int i = 0; i < n; i++) {
    u.push(1.0);
    v.push(0.0);
    scratch.push(0.0);
  }
  for (int i = 0; i < 10; i++) {
    _ata_times(u, v, scratch);
    _ata_times(v, u, scratch);
  }
  double uv = 0.0, vv = 0.0;
  for (int i = 0; i < n; i++) {
    uv += u[i] * v[i];
    vv += v[i] * v[i];
  }
  printf("%.9f\n", sqrt(uv / vv));
  return 0;
}

static void _ata_times(ArrayDbl input, ArrayDbl output, ArrayDbl scratch) {
  _multiply(input, scratch, 0);
  _multiply(scratch, output, 1);
}

static void _multiply(ArrayDbl input, ArrayDbl output, int transpose) {
  int n = input.len();
  if (n < 500) {
    if (transpose) _at_rows(input, output, 0, n);
    else _a_rows(input, output, 0, n);
    return;
  }
  auto {
    Array batches = [];
    for (int worker = 0; worker < 6; worker++) {
      Rows rows = Rows.new(input, output,
        n * worker / 6, n * (worker + 1) / 6, transpose);
      rows.worker = Thread.start(_calculate_rows, rows);
      batches.push(rows);
    }
    foreach (Rows rows in batches) {
      rows.worker.join();
      rows.worker.free();
    }
  }
}

static void Rows.init(Rows rows, ArrayDbl input, ArrayDbl output,
  int first, int last, int transpose) {
  rows.input = input;
  rows.output = output;
  rows.first = first;
  rows.last = last;
  rows.transpose = transpose;
}

static Var _calculate_rows(Var input) {
  Rows rows = input;
  if (rows.transpose) _at_rows(rows.input, rows.output, rows.first, rows.last);
  else _a_rows(rows.input, rows.output, rows.first, rows.last);
  return void;
}

static void _a_rows(ArrayDbl input, ArrayDbl output, int first, int last) {
  int n = input.len();
  for (int i = first; i < last; i++) {
    double sum = 0.0;
    for (int j = 0; j < n; j++)
      sum += _entry(i, j) * input[j];
    output[i] = sum;
  }
}

static double _entry(int i, int j) =>
  1.0 / ((i + j) * (i + j + 1) / 2 + i + 1);

static void _at_rows(ArrayDbl input, ArrayDbl output, int first, int last) {
  int n = input.len();
  for (int i = first; i < last; i++) {
    double sum = 0.0;
    for (int j = 0; j < n; j++)
      sum += _entry(j, i) * input[j];
    output[i] = sum;
  }
}
