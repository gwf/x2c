/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/spectralnorm-ported ported.x
 *   /tmp/spectralnorm-ported 2000
 */

/* The Computer Language Benchmarks Game
 * https://benchmarksgame-team.pages.debian.net/benchmarksgame/
 *
 * Based on the spectral-norm program contributed by Sebastien Loisel.
 * Distributed under the 3-Clause BSD License in LICENSE.md at:
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static double _eval_a(int i, int j) {
  int ij = i + j;
  return 1.0 / (ij * (ij + 1) / 2 + i + 1);
}

static void _eval_a_times_u(int n, const double u[], double out[]) {
  for (int i = 0; i < n; i++) {
    double sum = 0.0;
    for (int j = 0; j < n; j++) sum += _eval_a(i, j) * u[j];
    out[i] = sum;
  }
}

static void _eval_at_times_u(int n, const double u[], double out[]) {
  for (int i = 0; i < n; i++) {
    double sum = 0.0;
    for (int j = 0; j < n; j++) sum += _eval_a(j, i) * u[j];
    out[i] = sum;
  }
}

static void _eval_ata_times_u(
  int n, const double u[], double out[], double tmp[]) {
  _eval_a_times_u(n, u, tmp);
  _eval_at_times_u(n, tmp, out);
}

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 100;
  double *u = Scope.calloc((size_t) n, sizeof(double));
  double *v = Scope.calloc((size_t) n, sizeof(double));
  double *tmp = Scope.calloc((size_t) n, sizeof(double));

  for (int i = 0; i < n; i++) u[i] = 1.0;
  for (int i = 0; i < 10; i++) {
    _eval_ata_times_u(n, u, v, tmp);
    _eval_ata_times_u(n, v, u, tmp);
  }

  double v_bv = 0.0, vv = 0.0;
  for (int i = 0; i < n; i++) {
    v_bv += u[i] * v[i];
    vv += v[i] * v[i];
  }
  printf("%.9f\n", sqrt(v_bv / vv));
  return 0;
}
