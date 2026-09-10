/*  autodiff-checkpoint.x -- tape memory and time of reverse-mode variants

    Runs the gradient of one long relaxation loop with full recording or
    with checkpointing at several block sizes, one variant per process so
    peak resident memory isolates the tape. Usage: MODE [STEPS], where MODE
    is primal, full, k16, k64, k256, or k1024.
*/

#include "x2c.x"
#include "typed-array.x"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <sys/resource.h>
$(import "autodiff.xmacro")

$ad.reverse()
static double full(double x, double y, int steps) {
  double s = x;
  for (int i = 0; i < steps; i++) s += 0.001 * (y - s) * cos(s * 0.01);
  return s;
}

$ad.checkpoint(16)
static double k16(double x, double y, int steps) {
  double s = x;
  for (int i = 0; i < steps; i++) s += 0.001 * (y - s) * cos(s * 0.01);
  return s;
}

$ad.checkpoint(64)
static double k64(double x, double y, int steps) {
  double s = x;
  for (int i = 0; i < steps; i++) s += 0.001 * (y - s) * cos(s * 0.01);
  return s;
}

$ad.checkpoint(256)
static double k256(double x, double y, int steps) {
  double s = x;
  for (int i = 0; i < steps; i++) s += 0.001 * (y - s) * cos(s * 0.01);
  return s;
}

$ad.checkpoint(1024)
static double k1024(double x, double y, int steps) {
  double s = x;
  for (int i = 0; i < steps; i++) s += 0.001 * (y - s) * cos(s * 0.01);
  return s;
}

int main(int argc, char **argv) {
  const char *mode = argc > 1 ? argv[1] : "full";
  int steps = argc > 2 ? atoi(argv[2]) : 2000000;
  double x_grad = 0.0, y_grad = 0.0, value;
  clock_t start = clock();
  double (*variant)(double, double, int, double *, double *) = NULL;
  if (!strcmp(mode, "full")) variant = full_grad;
  else if (!strcmp(mode, "k16")) variant = k16_grad;
  else if (!strcmp(mode, "k64")) variant = k64_grad;
  else if (!strcmp(mode, "k256")) variant = k256_grad;
  else if (!strcmp(mode, "k1024")) variant = k1024_grad;
  else if (strcmp(mode, "primal")) return 2;
  if (variant) value = variant(1.0, 3.0, steps, &x_grad, &y_grad);
  else value = full(1.0, 3.0, steps);
  double seconds = (double) (clock() - start) / CLOCKS_PER_SEC;
  struct rusage usage;
  getrusage(RUSAGE_SELF, &usage);
  printf("%-7s steps %d value %.9f dy %.9f time %.3fs maxrss %.1f MB\n",
         mode, steps, value, y_grad, seconds,
         (double) usage.ru_maxrss / (1024.0 * 1024.0));
  return 0;
}
