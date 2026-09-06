/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int limit = atoi(argv[1]);
  int iterations = atoi(argv[2]);
  uint32_t checksum = 0;

  for (int run = 0; run < iterations; run++) {
    unsigned char *prime = calloc((size_t) limit + 1, 1);
    if (!prime) return 1;
    for (int i = 2; i <= limit; i++) prime[i] = 1;
    for (int p = 2; p <= limit / p; p++)
      if (prime[p])
        for (int multiple = p * p; multiple <= limit; multiple += p)
          prime[multiple] = 0;

    int last = 2, count = 1;
    for (int n = 3; n <= limit; n += 2)
      if (prime[n]) {
        last = n;
        count++;
      }
    checksum += last + count;
    free(prime);
  }
  printf("%u\n", checksum);
  return 0;
}
