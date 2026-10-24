/*  unalias-scopes.x -- removing an alias in the scope that declares it

    After `unalias name;` the name means what it meant before the alias, and
    the same scope may declare it again: in a block, at file scope, and in
    struct and enum bodies, where the removal needs no comma. A template
    may remove its own alias. `unalias` stays an ordinary name elsewhere.
*/

#include "x2c.x"

alias 100 as hundred;
static int before(void) { return hundred; }
unalias hundred;
static int hundred = 3;

enum Kinds {
  alias 10 as base;
  A = base,
  unalias base;
  alias 20 as base;
  B = base
};

typedef struct Grid {
  alias 3 as side;
  int first[side];
  unalias side;
  alias 2 as side;
  int second[side];
} Grid;

macro Stmt $bump_then_restore(Expr $target) {
  alias $target as t;
  t += 1;
  unalias t;
  int t = 0;
  (void) t;
}

int main(void) {
  int x = 1;
  alias x as y;
  y = 2;
  unalias y;
  int y = 9;
  $bump_then_restore(x);
  printf("%d %d %d %d %d %d\n", before(), hundred, A, B,
         (int) (sizeof(Grid) / sizeof(int)), x + y);
  int unalias = 1;
  unalias += 1;
  printf("%d\n", unalias);
  return 0;
}
