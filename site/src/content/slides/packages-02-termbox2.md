---
section: packages
tab: termbox2
title: A little life in your terminal.
image: packages/game-of-life.gif
imagePoster: packages/game-of-life-poster.png
imageAlt: A twenty-second recording of green Game of Life cells evolving in a terminal.
imageWidth: 680
imageHeight: 426
---

<!-- ignore: source excerpt; the complete example requires its optional package and setup. -->
```x2c,ignore
import "termbox2" with Termbox;

static void _draw(
  Termbox terminal, ArrayChar cells,
  int width, int height
) {
  terminal.clear();
  for (int y = 0; y < height; y++)
    for (int x = 0; x < width; x++) {
      if (!cells[y * width + x]) continue;
      int run = 1;
      while (x + run < width &&
             cells[y * width + x + run])
        run++;
      terminal.fill(
        x, y, run, 1, %"#",
        TB_GREEN | TB_BOLD, TB_DEFAULT
      );
      x += run - 1;
    }
  terminal.present();
}
```

Conway's Game of Life fills the terminal with a changing world. The
drawing function paints adjacent living cells in one call, then presents
the frame. The complete program starts with random cells, advances each
generation, handles resizing, and exits on a keypress.

[Full example](https://github.com/gwf/x2c/blob/main/packages/termbox2/examples/game-of-life.x) / [Package guide](https://github.com/gwf/x2c/blob/main/packages/termbox2/README.md)
