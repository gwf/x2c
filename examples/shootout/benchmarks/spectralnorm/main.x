/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/spectralnorm-idiomatic main.x
 *   /tmp/spectralnorm-idiomatic 2000
 */

/* SPDX-License-Identifier: BSD-3-Clause */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "typed-array.x"

static double _eval_a(int i, int j) {
  int ij = i + j;
  return 1.0 / (ij * (ij + 1) / 2 + i + 1);
}

/* x2c has no `restrict`, so out may alias u as far as the compiler can tell.
   Naming the row sum keeps it in a register instead of reloading out[i] on
   every step, which is also the clearer way to say what the row is. */
static void _eval_a_times_u(int n, ArrayDbl u, ArrayDbl out) {
  for (int i = 0; i < n; i++) {
    double sum = 0.0;
    for (int j = 0; j < n; j++) sum += _eval_a(i, j) * u[j];
    out[i] = sum;
  }
}

static void _eval_at_times_u(int n, ArrayDbl u, ArrayDbl out) {
  for (int i = 0; i < n; i++) {
    double sum = 0.0;
    for (int j = 0; j < n; j++) sum += _eval_a(j, i) * u[j];
    out[i] = sum;
  }
}

/* The scratch row holds one intermediate sweep; its length is the order of
   the matrix and it outlives every sweep. */
static void _eval_ata_times_u(ArrayDbl scratch, ArrayDbl u, ArrayDbl out) {
  int n = (int) scratch.len();
  _eval_a_times_u(n, u, scratch);
  _eval_at_times_u(n, scratch, out);
}

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 100;
  ArrayDbl u = ArrayDbl.new();
  for (int i = 0; i < n; i++) u.push(1.0);
  ArrayDbl v = u.copy(), scratch = u.copy();

  for (int i = 0; i < 10; i++) {
    _eval_ata_times_u(scratch, u, v);
    _eval_ata_times_u(scratch, v, u);
  }

  double v_bv = 0.0, vv = 0.0;
  for (int i = 0; i < n; i++) {
    v_bv += u[i] * v[i];
    vv += v[i] * v[i];
  }
  printf("%.9f\n", sqrt(v_bv / vv));
  return 0;
}
