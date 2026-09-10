---
title: You are X. Lisp is O.
image: examples/tic-tac-toe.svg
imageAlt: A tic-tac-toe position with X in squares 1 and 2, O in the center and square 3. O has blocked X's top row.
imageWidth: 640
imageHeight: 390
---

<!-- ignore: native bindings, interpreter setup, and move-call excerpts. -->
```x2c,ignore
$lisp.binding(game, "empty?")
static Var _open(int square) {
  if (_empty(square)) return <true>;
  return %();
}

$lisp.binding(game, "wins?")
static Var _wins(int square, String player) {
  if (!_empty(square)) return %();
  char saved = board[square - 1];
  board[square - 1] = player == %"X" ? 'X' : 'O';
  int won = _won(board[square - 1]);
  board[square - 1] = saved;
  if (won) return <true>;
  return %();
}

Lisp lisp = Lisp.new();
defer lisp.destroy();
$lisp.install(lisp, game);
File strategy = File.open(argv[1], "r");
defer strategy.close();
Lisp.eval_file(lisp, strategy);

// On each O turn:
square = lisp.eval(%(choose-move));
```

The binding decorator exposes `empty?` and `wins?` to Lisp.
`wins?` tries a move and restores the square afterward, so the script
can ask about the native board without keeping a second copy.

<section class="code-note" data-code-line="18">

### Load the opponent.

Install the bindings, load the strategy, then call `choose-move` on each
O turn. It returns a square number; the host checks and plays it.

</section>
