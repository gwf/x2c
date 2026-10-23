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
    for (int y = 0; y < h; y++) {
      int above = ((y + h - 1) % h) * w;
      int row = y * w, below = ((y + 1) % h) * w;
      for (int x = 0; x < w; x++) {
        int left = (x + w - 1) % w, right = (x + 1) % w;
        int neighbors = cells[above + left] + cells[above + x]
          + cells[above + right] + cells[row + left] + cells[row + right]
          + cells[below + left] + cells[below + x] + cells[below + right];
        int i = row + x;
        next[i] = neighbors == 3 || (cells[i] && neighbors == 2);
      }
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
