/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/gameoflife-idiomatic main.x
 *   /tmp/gameoflife-idiomatic 192 128 100
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include "typed-array.x"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  int w = atoi(argv[1]), h = atoi(argv[2]), steps = atoi(argv[3]);
  ArrayChar cells = ArrayChar.new(), next = ArrayChar.new();
  for (int i = 0; i < w * h; i++) {
    cells.push((i * 17 + i / w * 23) % 11 == 0);
    next.push(0);
  }
  for (int step = 0; step < steps; step++) {
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++) {
        int neighbors = 0;
        for (int dy = -1; dy <= 1; dy++)
          for (int dx = -1; dx <= 1; dx++)
            if (dx || dy)
              neighbors += cells[((y + dy + h) % h) * w + (x + dx + w) % w];
        int i = y * w + x;
        next[i] = neighbors == 3 || (cells[i] && neighbors == 2);
      }
    ArrayChar swap = cells;
    cells = next;
    next = swap;
  }
  uint32_t hash = 2166136261u;
  foreach (char cell, cells) hash = (hash ^ cell) * 16777619u;
  printf("%u\n", hash);
  return 0;
}
