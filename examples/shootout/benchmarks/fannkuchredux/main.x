/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 *
 * Adapted from the contributions recorded in ../../benchmarks.json.
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 7;
  printf("Pfannkuchen(%d) = %d\n", n, _fannkuch(n));
  return 0;
}

static int _fannkuch(int n) {
  Array permutation = [], working = [], counts = [];
  for (int i = 0; i < n; i++) {
    permutation.push(i);
    working.push(i);
    counts.push(i + 1);
  }
  int maximum = 0, checksum = 0, permutation_count = 0;
  do {
    working.setslice(0, n, permutation);
    int flips = 0;
    for (int k = working[0].int(); k; k = working[0].int()) {
      for (int i = 0, j = k; i < j; i++, j--) {
        Var value = working[i];
        working[i] = working[j];
        working[j] = value;
      }
      flips++;
    }
    if (flips > maximum) maximum = flips;
    checksum += permutation_count++ % 2 ? -flips : flips;
  } while (_advance(permutation, counts, n));
  printf("%d\n", checksum);
  return maximum;
}

static int _advance(Array permutation, Array counts, int n) {
  for (int r = 1; r < n; r++) {
    Var first = permutation[0];
    for (int i = 0; i < r; i++) permutation[i] = permutation[i + 1];
    permutation[r] = first;
    int remaining = counts[r].int() - 1;
    counts[r] = remaining;
    if (remaining) return 1;
    counts[r] = r + 1;
  }
  return 0;
}
