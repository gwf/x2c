---
slug: embedded-lisp
navTitle: Play against Lisp
order: 2
slide: runtime-lisp
title: Give your game a Lisp player.
description: Play tic-tac-toe against a Lisp strategy inside a native x2c program.
source: examples/magic/tic-tac-toe.x
sourceDownload: examples/embedded-lisp/tic-tac-toe.x.txt
codeLabel: tic-tac-toe.x / bindings and interpreter excerpts
extraPanels: [embedded-lisp-strategy]
runIntro: Build the game, then play as X. Enter a square number to move.
run: |
  ./x2c build --output /tmp/tic-tac-toe examples/magic/tic-tac-toe.x
  /tmp/tic-tac-toe examples/magic/tic-tac-toe.xlisp
guide: docs/library/modules/lisp.html
---

## Write a better opponent.

The strategy takes a win, blocks yours, then prefers the center, corners,
and edges. It can miss forks. Teach it to look further ahead by editing
[the Lisp file](./tic-tac-toe.xlisp.txt), then run the same executable again.

The [complete x2c source](./tic-tac-toe.x.txt) and strategy are included here.
