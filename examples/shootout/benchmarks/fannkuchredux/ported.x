/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/fannkuchredux-ported ported.x
 *   /tmp/fannkuchredux-ported 10
 */

/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 *
 * converted to C by Joseph Piche
 * from the Java version by Oleg Mazurov and Isaac Gouy
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Copy perm1 into perm, then keep reversing the leading perm[0] + 1 entries
 * until the front entry is 0, and report how many reversals that took. */
static inline int _flips(const int *perm1, int *perm, int n) {
  memcpy(perm, perm1, n * sizeof(int));

  int flips = 0;
  for (int k = perm[0]; k != 0; k = perm[0]) {
    for (int i = 0, j = k; i < j; i++, j--) {
      int temp = perm[i];
      perm[i] = perm[j];
      perm[j] = temp;
    }
    flips++;
  }
  return flips;
}

/* Step to the next permutation: rotate the leading r + 1 entries of perm1
 * left, spend one turn of digit r on the count odometer, and carry into a
 * wider rotation when that digit runs out. Refilling the spent digit here
 * is what lets the next step start over at r = 1. Returns 0 once the
 * odometer has wrapped and every permutation has been visited. */
static inline int _advance(int *perm1, int *count, int n) {
  for (int r = 1; r != n; r++) {
    int first = perm1[0];
    for (int i = 0; i < r; i++)
      perm1[i] = perm1[i + 1];
    perm1[r] = first;
    if (--count[r] > 0)
      return 1;
    count[r] = r + 1;
  }
  return 0;
}

static int _fannkuchredux(int n) {
  int *perm = Scope.malloc(n * sizeof(int));
  int *perm1 = Scope.malloc(n * sizeof(int));
  int *count = Scope.malloc(n * sizeof(int));
  for (int i = 0; i < n; i++) {
    perm1[i] = i;
    count[i] = i + 1;
  }

  int max_flips_count = 0, checksum = 0, perm_count = 0;
  do {
    int flips_count = _flips(perm1, perm, n);
    if (flips_count > max_flips_count)
      max_flips_count = flips_count;
    checksum += perm_count++ % 2 == 0 ? flips_count : -flips_count;
  } while (_advance(perm1, count, n));

  printf("%d\n", checksum);
  return max_flips_count;
}

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 7;
  printf("Pfannkuchen(%d) = %d\n", n, _fannkuchredux(n));
  return 0;
}
