/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/fannkuchredux-idiomatic main.x
 *   /tmp/fannkuchredux-idiomatic 10
 */

/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdio.h>
#include <stdlib.h>
#include "typed-array.x"

/* Step to the next permutation: rotate the leading r + 1 entries left, spend
 * one turn of digit r on the count odometer, and carry into a wider rotation
 * when that digit runs out. Refilling the spent digit here is what lets the
 * next round start over at r = 1, so the caller needs no reset loop.
 * Returns 0 once the odometer has wrapped and every permutation is visited. */
static int _advance(ArrayInt perm, ArrayInt count, int n) {
  for (int r = 1; r != n; r++) {
    int first = perm[0];
    for (int i = 0; i < r; i++) perm[i] = perm[i + 1];
    perm[r] = first;
    int remaining = --count[r];
    if (remaining > 0) return 1;
    count[r] = r + 1;
  }
  return 0;
}

static int _fannkuch(int n) {
  ArrayInt permutation = ArrayInt.new(), working = ArrayInt.new(),
           counts = ArrayInt.new();
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

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 7;
  printf("Pfannkuchen(%d) = %d\n", n, _fannkuch(n));
  return 0;
}
