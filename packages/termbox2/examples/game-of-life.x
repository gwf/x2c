/*  game-of-life.x -- toroidal Life in the current terminal cells. */

import "termbox2" with Termbox;
#include "typed-array.x"
#include <stdlib.h>
#include <time.h>

static ArrayChar _world(int width, int height) {
  ArrayChar cells = ArrayChar.new();
  for (int i = 0; i < width * height; i++)
    cells.push(rand() > RAND_MAX / 2);
  return cells;
}

static void _advance(ArrayChar cells, ArrayChar next, int width, int height) {
  for (int y = 0; y < height; y++)
    for (int x = 0; x < width; x++) {
      int neighbors = 0;
      for (int dy = -1; dy <= 1; dy++)
        for (int dx = -1; dx <= 1; dx++)
          if (dx || dy)
            neighbors += cells[((y + dy + height) % height) * width +
                               (x + dx + width) % width];
      int i = y * width + x;
      next[i] = neighbors == 3 || (cells[i] && neighbors == 2);
    }
}

static void _draw(Termbox terminal, ArrayChar cells, int width, int height) {
  terminal.clear();
  for (int y = 0; y < height; y++)
    for (int x = 0; x < width; x++) {
      if (!cells[y * width + x]) continue;
      int run = 1;
      while (x + run < width && cells[y * width + x + run]) run++;
      terminal.fill(x, y, run, 1, %"#", TB_GREEN | TB_BOLD, TB_DEFAULT);
      x += run - 1;
    }
  terminal.present();
}

int main(void) {
  srand((unsigned int) time(NULL));
  Termbox terminal = Termbox.open();
  defer terminal.close();
  terminal.hide_cursor();

  int width = terminal.width(), height = terminal.height();
  ArrayChar cells = _world(width, height), next = _world(width, height);

  while (1) {
    if (width != terminal.width() || height != terminal.height()) {
      width = terminal.width();
      height = terminal.height();
      cells = _world(width, height);
      next = _world(width, height);
    }
    _draw(terminal, cells, width, height);
    if (terminal.peek(80).is_key()) break;
    _advance(cells, next, width, height);
    ArrayChar swap = cells;
    cells = next;
    next = swap;
  }
  return 0;
}
