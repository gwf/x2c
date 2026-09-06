/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/sieve-idiomatic main.x
 *   /tmp/sieve-idiomatic 500000 5
 */

/* SPDX-License-Identifier: BSD-3-Clause */

#include "typed-array.x"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 3) return 2;
  int limit = atoi(argv[1]), iterations = atoi(argv[2]);
  uint32_t checksum = 0;

  for (int run = 0; run < iterations; run++) {
    Scope.retain();
    /* One packed byte per number, grown and zeroed once; the Array owns the
       storage and the Scope frees it. The marking passes borrow the buffer
       instead of indexing the Array: a byte store may alias anything, so the
       element base cannot stay in a register across one, and the sieve is
       nothing but byte stores. Wider elements do not have this problem. */
    ArrayChar prime = ArrayChar.new();
    char *flag = prime.bytes.append(NULL, (size_t) limit + 1);
    for (int i = 2; i <= limit; i++) flag[i] = 1;
    for (int p = 2; p <= limit / p; p++)
      if (flag[p])
        for (int multiple = p * p; multiple <= limit; multiple += p)
          flag[multiple] = 0;

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
