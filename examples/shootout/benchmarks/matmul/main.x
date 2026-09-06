/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/matmul-idiomatic main.x
 *   /tmp/matmul-idiomatic 180 4
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include "typed-array.x"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int n = atoi(argv[1]), runs = atoi(argv[2]);
  ArrayDbl a = ArrayDbl.new(), b = ArrayDbl.new(), c = ArrayDbl.new();
  for (int i = 0; i < n; i++)
    for (int j = 0; j < n; j++) {
      a.push((double) ((i * 31 + j * 17) % 100) / 100.0);
      b.push((double) ((i * 13 + j * 29) % 100) / 100.0);
      c.push(0.0);
    }
  double checksum = 0;
  for (int run = 0; run < runs; run++) {
    for (int i = 0; i < n; i++)
      for (int j = 0; j < n; j++) {
        double sum = 0;
        for (int k = 0; k < n; k++) sum += a[i * n + k] * b[k * n + j];
        c[i * n + j] = sum;
      }
    checksum += c[(run * 97) % (n * n)];
  }
  printf("%.9f\n", checksum);
  return 0;
}
