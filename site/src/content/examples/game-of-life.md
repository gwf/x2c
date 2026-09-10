---
slug: game-of-life
slide: game-of-life
title: A little life in your terminal.
description: Conway's Game of Life, drawn in a terminal with the termbox2 package.
source: packages/termbox2/examples/game-of-life.x
codeLabel: Complete program
runIntro: Build x2c, prepare termbox2, and run the simulation in your terminal. Any key exits.
run: |
  ./configure --packages termbox2
  make -C packages/termbox2 short-example
  ./packages/termbox2/builds/game-of-life
guide: docs/guide/packages.html
---

## Bring a real terminal.

The termbox2 package needs its own dependency preparation. Package builds are
currently tested on macOS. `./configure --packages termbox2` reports missing
prerequisites; it does not install them. The build then prepares the pinned
dependency as needed. Interactive play does not require Expect.

The <a href="https://github.com/gwf/x2c/blob/main/packages/termbox2/README.md" data-example-action="guide">package guide</a>
covers drawing, input, and the terminal's lifetime.
