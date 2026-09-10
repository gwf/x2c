---
title: Choose a move.
codeLabel: tic-tac-toe.xlisp / complete strategy
---

```xlisp
(def squares '(1 2 3 4 5 6 7 8 9))

(defun first-move (predicate choices)
  (if (null? choices)
    nil
    (if (predicate (car choices))
      (car choices)
      (first-move predicate (cdr choices)))))

(defun winning-move (player)
  (first-move (lambda (square) (wins? square player)) squares))

(defun choose-move ()
  (or (winning-move "O")
      (winning-move "X")
      (first-move empty? '(5 1 3 7 9 2 4 6 8))))
```

Try to win, then block X. Otherwise, take the first free square in the
preference list: center, corners, edges. `or` stops at the first move found.

[Edit this strategy](./tic-tac-toe.xlisp.txt) to change the opponent
without rebuilding the game.
