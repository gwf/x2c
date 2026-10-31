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

static inline int _max(int a, int b) {
  return a > b ? a : b;
}

static int _fannkuchredux(int n) {
  int perm[n];
  int perm1[n];
  int count[n];
  int max_flips_count = 0;
  int perm_count = 0;
  int checksum = 0;

  for (int i = 0; i < n; i++)
    perm1[i] = i;

  int r = n;
  while (1) {
    while (r != 1) {
      count[r - 1] = r;
      r--;
    }

    for (int i = 0; i < n; i++)
      perm[i] = perm1[i];

    int flips_count = 0;
    int k;
    while ((k = perm[0]) != 0) {
      int half = (k + 1) >> 1;
      for (int i = 0; i < half; i++) {
        int temp = perm[i];
        perm[i] = perm[k - i];
        perm[k - i] = temp;
      }
      flips_count++;
    }

    max_flips_count = _max(max_flips_count, flips_count);
    checksum += perm_count % 2 == 0 ? flips_count : -flips_count;

    /* Use incremental change to generate another permutation. */
    while (1) {
      if (r == n) {
        printf("%d\n", checksum);
        return max_flips_count;
      }

      int first = perm1[0];
      int i = 0;
      while (i < r) {
        int next = i + 1;
        perm1[i] = perm1[next];
        i = next;
      }
      perm1[r] = first;
      count[r]--;
      if (count[r] > 0)
        break;
      r++;
    }
    perm_count++;
  }
}

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 7;
  printf("Pfannkuchen(%d) = %d\n", n, _fannkuchredux(n));
  return 0;
}
