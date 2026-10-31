/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void sort(int *a, int left, int right) {
  int i = left, j = right, pivot = a[(left + right) / 2];
  while (i <= j) {
    while (a[i] < pivot) i++;
    while (a[j] > pivot) j--;
    if (i <= j) {
      int swap = a[i]; a[i++] = a[j]; a[j--] = swap;
    }
  }
  if (left < j) sort(a, left, j);
  if (i < right) sort(a, i, right);
}

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int n = atoi(argv[1]), runs = atoi(argv[2]);
  int *data = malloc(n * sizeof(int)), *copy = malloc(n * sizeof(int));
  uint32_t state = 1, checksum = 0;
  for (int i = 0; i < n; i++) {
    state = state * 1664525u + 1013904223u;
    data[i] = state & 0x7fffffff;
  }
  for (int run = 0; run < runs; run++) {
    memcpy(copy, data, n * sizeof(int));
    sort(copy, 0, n - 1);
    checksum += copy[(run * 97) % n];
  }
  printf("%u\n", checksum);
  free(data); free(copy);
  return 0;
}
