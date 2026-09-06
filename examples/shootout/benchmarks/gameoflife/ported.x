/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/gameoflife-ported ported.x
 *   /tmp/gameoflife-ported 192 128 100
 */

/* SPDX-License-Identifier: BSD-3-Clause */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct Grid { unsigned char *alive; int w, h; } Grid;

/* The board is a torus, so every read wraps on both axes. */
static inline int Grid.at(Grid g, int x, int y) {
  return g.alive[((y + g.h) % g.h) * g.w + (x + g.w) % g.w];
}

int main(int argc, char **argv) {
  if (argc != 4) return 2;
  int w = atoi(argv[1]), h = atoi(argv[2]), steps = atoi(argv[3]);
  int n = w * h;
  Grid cells = { Scope.malloc(n), w, h }, next = { Scope.malloc(n), w, h };
  for (int i = 0; i < n; i++) cells.alive[i] = (i * 17 + i / w * 23) % 11 == 0;
  for (int step = 0; step < steps; step++) {
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++) {
        int neighbors = 0;
        for (int dy = -1; dy <= 1; dy++)
          for (int dx = -1; dx <= 1; dx++)
            if (dx || dy) neighbors += cells.at(x + dx, y + dy);
        int i = y * w + x;
        next.alive[i] = neighbors == 3 || (cells.alive[i] && neighbors == 2);
      }
    Grid swap = cells; cells = next; next = swap;
  }
  uint32_t hash = 2166136261u;
  for (int i = 0; i < n; i++) hash = (hash ^ cells.alive[i]) * 16777619u;
  printf("%u\n", hash);
  return 0;
}
