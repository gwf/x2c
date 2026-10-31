/* SPDX-License-Identifier: BSD-3-Clause */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint32_t hash_byte(uint32_t hash, unsigned byte) {
  return (hash << 5) + hash + byte;
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  int width = atoi(argv[1]);
  int height = atoi(argv[2]);
  int iterations = atoi(argv[3]);
  uint32_t hash = 5381;

  for (int run = 0; run < iterations; run++) {
    char header[64];
    int header_len = snprintf(header, sizeof(header), "P4\n%d %d\n",
                              width, height);
    for (int i = 0; i < header_len; i++)
      hash = hash_byte(hash, (unsigned char) header[i]);

    for (int y = 0; y < height; y++) {
      int bit_count = 0;
      unsigned byte = 0;
      for (int x = 0; x < width; x++) {
        double zr = 0, zi = 0, tr = 0, ti = 0;
        double cr = 2.0 * x / width - 1.5;
        double ci = 2.0 * y / height - 1.0;
        int i = 0;
        while (i++ < 50 && tr + ti <= 4.0) {
          zi = 2.0 * zr * zi + ci;
          zr = tr - ti + cr;
          tr = zr * zr;
          ti = zi * zi;
        }
        byte = (byte << 1) | (tr + ti <= 4.0);
        if (++bit_count == 8) {
          hash = hash_byte(hash, byte);
          bit_count = byte = 0;
        }
      }
      if (bit_count)
        hash = hash_byte(hash, byte << (8 - bit_count));
    }
  }
  printf("%u\n", hash);
  return 0;
}
