/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 *
 * Adapted from the contributed implementations recorded in benchmark.json.
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

static void _a_times(ArrayDbl input, ArrayDbl output) {
  int n = input.len();
  for (int i = 0; i < n; i++) {
    double sum = 0.0;
    for (int j = 0; j < n; j++) sum += _entry(i, j) * input[j];
    output[i] = sum;
  }
}

static double _entry(int i, int j) =>
  1.0 / ((i + j) * (i + j + 1) / 2 + i + 1);

static void _at_times(ArrayDbl input, ArrayDbl output) {
  int n = input.len();
  for (int i = 0; i < n; i++) {
    double sum = 0.0;
    for (int j = 0; j < n; j++) sum += _entry(j, i) * input[j];
    output[i] = sum;
  }
}
