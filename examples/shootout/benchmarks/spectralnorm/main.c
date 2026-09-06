/* The Computer Language Benchmarks Game
 * https://benchmarksgame-team.pages.debian.net/benchmarksgame/
 *
 * Based on the spectral-norm program contributed by Sebastien Loisel.
 * Distributed under the 3-Clause BSD License:
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/-/blob/master/LICENSE.md
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static double eval_a(int i, int j) {
  int ij = i + j;
  return 1.0 / (ij * (ij + 1) / 2 + i + 1);
}

static void eval_a_times_u(int n, const double u[], double out[]) {
  for (int i = 0; i < n; i++) {
    out[i] = 0.0;
    for (int j = 0; j < n; j++)
      out[i] += eval_a(i, j) * u[j];
  }
}

static void eval_at_times_u(int n, const double u[], double out[]) {
  for (int i = 0; i < n; i++) {
    out[i] = 0.0;
    for (int j = 0; j < n; j++)
      out[i] += eval_a(j, i) * u[j];
  }
}

static void eval_ata_times_u(int n, const double u[], double out[]) {
  double tmp[n];
  eval_a_times_u(n, u, tmp);
  eval_at_times_u(n, tmp, out);
}

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 100;
  double u[n], v[n];

  for (int i = 0; i < n; i++)
    u[i] = 1.0;
  for (int i = 0; i < 10; i++) {
    eval_ata_times_u(n, u, v);
    eval_ata_times_u(n, v, u);
  }

  double v_bv = 0.0, vv = 0.0;
  for (int i = 0; i < n; i++) {
    v_bv += u[i] * v[i];
    vv += v[i] * v[i];
  }
  printf("%.9f\n", sqrt(v_bv / vv));
  return 0;
}
