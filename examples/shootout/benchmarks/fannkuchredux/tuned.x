/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 *
 * Adapted from the contributions recorded in ../../benchmarks.json.
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>
#include <stdlib.h>
#include "typed-array.x"

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 7;
  printf("Pfannkuchen(%d) = %d\n", n, _fannkuch(n));
  return 0;
}

static int _fannkuch(int n) {
  ArrayInt permutation = ArrayInt.new(), working = ArrayInt.new();
  ArrayInt counts = ArrayInt.new();
  for (int i = 0; i < n; i++) {
    permutation.push(i);
    working.push(i);
    counts.push(i + 1);
  }
  int maximum = 0, checksum = 0, permutation_count = 0;
  do {
    for (int i = 0; i < n; i++) working[i] = permutation[i];
    int flips = 0;
    for (int k = working[0]; k; k = working[0]) {
      for (int i = 0, j = k; i < j; i++, j--) {
        int value = working[i];
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

static int _advance(ArrayInt permutation, ArrayInt counts, int n) {
  for (int r = 1; r < n; r++) {
    int first = permutation[0];
    for (int i = 0; i < r; i++) permutation[i] = permutation[i + 1];
    permutation[r] = first;
    int remaining = counts[r] - 1;
    counts[r] = remaining;
    if (remaining) return 1;
    counts[r] = r + 1;
  }
  return 0;
}
