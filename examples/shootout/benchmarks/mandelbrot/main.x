/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 *
 * Adapted from the contributed implementations recorded in benchmark.json.
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  int size = atoi(argv[1]);
  printf("P4\n%d %d\n", size, size);
  for (int y = 0; y < size; y++) auto {
    Array row = [];
    for (int x = 0; x < size; x += 8) {
      int bits = size - x < 8 ? size - x : 8;
      unsigned byte = 0;
      for (int b = 0; b < bits; b++)
        byte = (byte << 1) | _inside(x + b, y, size);
      row.push(byte << (8 - bits));
    }
    foreach (int byte in row) putchar(byte);
  }
  return 0;
}

static unsigned _inside(int x, int y, int size) {
  double zr = 0.0, zi = 0.0, tr = 0.0, ti = 0.0;
  double cr = 2.0 * x / size - 1.5, ci = 2.0 * y / size - 1.0;
  for (int i = 0; i < 50 && tr + ti <= 4.0; i++) {
    zi = 2.0 * zr * zi + ci;
    zr = tr - ti + cr;
    tr = zr * zr;
    ti = zi * zi;
  }
  return tr + ti <= 4.0;
}
