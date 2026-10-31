/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int n = atoi(argv[1]), runs = atoi(argv[2]);
  size_t count = (size_t)n * n;
  double *a = malloc(count * sizeof(double));
  double *b = malloc(count * sizeof(double));
  double *c = malloc(count * sizeof(double));
  for (int i = 0; i < n; i++)
    for (int j = 0; j < n; j++) {
      a[i * n + j] = (double)((i * 31 + j * 17) % 100) / 100.0;
      b[i * n + j] = (double)((i * 13 + j * 29) % 100) / 100.0;
    }
  double checksum = 0;
  for (int run = 0; run < runs; run++) {
    for (int i = 0; i < n; i++)
      for (int j = 0; j < n; j++) {
        double sum = 0;
        for (int k = 0; k < n; k++)
          sum += a[i * n + k] * b[k * n + j];
        c[i * n + j] = sum;
      }
    checksum += c[(run * 97) % count];
  }
  printf("%.9f\n", checksum);
  free(a); free(b); free(c);
  return 0;
}
