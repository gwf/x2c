/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/sieve-ported ported.x
 *   /tmp/sieve-ported 500000 5
 */

/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int limit = atoi(argv[1]), iterations = atoi(argv[2]);
  uint32_t checksum = 0;

  for (int run = 0; run < iterations; run++) {
    Scope.retain();
    unsigned char *prime = Scope.calloc((size_t) limit + 1, 1);
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
    Scope.release();
  }
  printf("%u\n", checksum);
  return 0;
}
