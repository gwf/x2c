/* A Stmt decorator's items land in the caller's block, so a variable it
   declares through the caller's `Name` is typed for the statements after
   it: a field boxed into a Var, a call argument, arithmetic, a `?:`, and a
   `foreach` source. */

#include "x2c.x"

typedef struct Move { int card; List cards; } Move;

macro Unit $make(Type $kind) {
  macro Decorator $moving(Stmt $body, Name $move) {
    $kind $move = {};
    {
      $body
      $move.card = 3;
      $move.cards = %(1 2);
    }
  }
}

$make(Move);

static int twice(int n) => n * 2;

int main(void) {
  $moving(m) puts("moving");
  Array cards = [];
  cards.push(m.card);
  int sum = 0;
  foreach (int card in m.cards) sum += card;
  printf("%d %d %d %d %d\n", (int) cards.len(), twice(m.card), m.card + 1,
         m.card ? m.card : -1, sum);
  return 0;
}
