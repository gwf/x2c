/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/mandelbrot-idiomatic main.x
 *   /tmp/mandelbrot-idiomatic 500 500 1
 */

/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint32_t _hash_byte(uint32_t hash, unsigned byte) {
  return (hash << 5) + hash + byte;
}

/* One pixel: 1 while the orbit of (cr, ci) has not escaped after 50 steps.
 * Each step is its own statement so clang contracts exactly what the C
 * contracts and the checksum stays bit-identical. */
static unsigned _in_set(int x, int y, int width, int height) {
  double zr = 0, zi = 0, tr = 0, ti = 0;
  double cr = 2.0 * x / width - 1.5, ci = 2.0 * y / height - 1.0;
  for (int i = 0; i < 50 && tr + ti <= 4.0; i++) {
    zi = 2.0 * zr * zi + ci;
    zr = tr - ti + cr;
    tr = zr * zr;
    ti = zi * zi;
  }
  return tr + ti <= 4.0;
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  int width = atoi(argv[1]), height = atoi(argv[2]);
  uint32_t hash = 5381;

  for (int run = atoi(argv[3]); run > 0; run--) {
    char header[64];
    int len = snprintf(header, sizeof(header), "P4\n%d %d\n", width, height);
    for (int i = 0; i < len; i++)
      hash = _hash_byte(hash, (unsigned char) header[i]);

    /* A PBM row is eight pixels to the byte, leftmost pixel in the high bit,
     * and a row that does not fill its last byte pads it on the right.
     * Walking the row a byte at a time says that outright, with no bit
     * counter carried across pixels. */
    for (int y = 0; y < height; y++)
      for (int x = 0; x < width; x += 8) {
        int bits = width - x < 8 ? width - x : 8;
        unsigned byte = 0;
        for (int b = 0; b < bits; b++)
          byte = (byte << 1) | _in_set(x + b, y, width, height);
        hash = _hash_byte(hash, byte << (8 - bits));
      }
  }
  printf("%u\n", hash);
  return 0;
}
