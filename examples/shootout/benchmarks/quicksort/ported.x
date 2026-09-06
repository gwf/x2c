/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/quicksort-ported ported.x
 *   /tmp/quicksort-ported 200000 10
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void _sort(int *a, int left, int right) {
  int i = left, j = right, pivot = a[(left + right) / 2];
  while (i <= j) {
    while (a[i] < pivot) i++;
    while (a[j] > pivot) j--;
    if (i <= j) {
      int swap = a[i]; a[i++] = a[j]; a[j--] = swap;
    }
  }
  if (left < j) _sort(a, left, j);
  if (i < right) _sort(a, i, right);
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int n = atoi(argv[1]), runs = atoi(argv[2]);
  int *data = Scope.malloc(n * sizeof(int));
  int *copy = Scope.malloc(n * sizeof(int));
  uint32_t state = 1, checksum = 0;
  for (int i = 0; i < n; i++) {
    state = state * 1664525u + 1013904223u;
    data[i] = state & 0x7fffffff;
  }
  for (int run = 0; run < runs; run++) {
    memcpy(copy, data, n * sizeof(int));
    _sort(copy, 0, n - 1);
    checksum += copy[(run * 97) % n];
  }
  printf("%u\n", checksum);
  return 0;
}
