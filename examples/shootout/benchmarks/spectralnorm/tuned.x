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
  _a_times(input, scratch);
  _at_times(scratch, output);
}

static void _a_times(ArrayDbl input, ArrayDbl output) =>
  _multiply(input, output, 0);

static void _at_times(ArrayDbl input, ArrayDbl output) =>
  _multiply(input, output, 1);

static void _multiply(ArrayDbl input, ArrayDbl output, int transpose) {
  int n = input.len();
  if (n < 500) {
    _rows(input, output, 0, n, transpose);
    return;
  }
  auto {
    Array jobs = [];
    for (int worker = 0; worker < 6; worker++)
      jobs.push(%!() => _rows(input, output,
        n * worker / 6, n * (worker + 1) / 6, transpose));
    Thread.run(jobs);
  }
}

static void _rows(ArrayDbl input, ArrayDbl output,
  int first, int last, int transpose) {
  int n = input.len();
  for (int i = first; i < last; i++) {
    double sum = 0.0;
    int denominator = transpose ? _entry(0, i) : _entry(i, 0);
    for (int j = 0; j < n; j++) {
      sum += (1.0 / denominator) * input[j];
      // Adjacent denominators differ by i + j + 1 (A), or i + j + 2 (At).
      denominator += i + j + 1 + transpose;
    }
    output[i] = sum;
  }
}

static int _entry(int i, int j) =>
  (i + j) * (i + j + 1) / 2 + i + 1;
