---
slug: game-of-life
section: packages
tab: termbox2
title: Drawing the world.
image: packages/game-of-life.gif
imagePoster: packages/game-of-life-poster.png
imageAlt: A twenty-second recording of green Game of Life cells evolving in a terminal.
imageWidth: 680
imageHeight: 426
---

<!-- ignore: complete program; requires the optional termbox2 package and setup. -->
```x2c,ignore
import "termbox2" with Termbox;
#include "typed-array.x"
#include <stdlib.h>
#include <time.h>

static void _draw(Termbox term, ArrayChar cells, int width, int height) {
  term.clear();
  for (int y = 0; y < height; y++)
    for (int x = 0; x < width; x++) {
      if (!cells[y * width + x]) continue;
      int run = 1;
      while (x + run < width && cells[y * width + x + run]) run++;
      term.fill(x, y, run, 1, %"#", TB_GREEN | TB_BOLD, TB_DEFAULT);
      x += run - 1;
    }
  term.present();
}

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

int main(void) {
  srand((unsigned int) time(NULL));
  Termbox term = Termbox.open();
  defer term.close();
  term.hide_cursor();

  int width = term.width(), height = term.height();
  ArrayChar cells = _world(width, height), next = _world(width, height);

  while (1) {
    if (width != term.width() || height != term.height()) {
      width = term.width();
      height = term.height();
      cells = _world(width, height);
      next = _world(width, height);
    }
    _draw(term, cells, width, height);
    if (term.peek(80).is_key()) break;
    _advance(cells, next, width, height);
    ArrayChar swap = cells;
    cells = next;
    next = swap;
  }
  return 0;
}
```

The animation records this program. `_draw` paints each run of adjacent
living cells with one `fill` call, then presents the frame.

<section class="code-note" data-code-line="19">

### The rules of Life.

Two `ArrayChar` values hold the world: one for the current generation, one
for the next. A cell survives with two or three living neighbors. An empty
cell becomes alive with exactly three. Everything else dies or stays empty.

Each update reads only from `cells` and writes only to `next`, so every cell
sees the same generation. The main loop swaps the two arrays after an
update, reusing their storage for the following generation.

The modulo expressions wrap both coordinates. A cell on the left edge has
neighbors on the right, and the top row touches the bottom. There are no
special edge rules.

`_world` starts roughly half the cells alive. Change that comparison to try
a sparser starting population.

</section>

<section class="code-note" data-code-line="40">

### Keep the world running.

Opening the terminal and registering its cleanup sit together:
`defer term.close()` restores it when the function exits. Hiding the cursor
keeps it out of the animation.

The world takes its dimensions from the terminal. Resizing replaces both
arrays with fresh random cells at the new size.

Each frame is drawn before `peek(80)` waits up to 80 milliseconds for input.
A keypress leaves the loop. Otherwise, the program calculates the next
generation and swaps the arrays. Lower the timeout for a faster simulation,
or raise it to watch patterns evolve more slowly.

[Full example](https://github.com/gwf/x2c/blob/main/packages/termbox2/examples/game-of-life.x) / [Package guide](https://github.com/gwf/x2c/blob/main/packages/termbox2/README.md)

</section>
