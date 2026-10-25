/*  unalias-reveals.x -- removal reveals the enclosing alias at once

    Removing a body's alias gives its name the meaning of the enclosing
    alias for the rest of the body: in declaration wrappers, nested
    wrappers, struct and enum bodies, a wrapper inside a struct body, and a
    wrapper over a `static` alias of the same name.
*/

#include "x2c.x"

alias 1 as mine;
static alias 7 as own;

alias 2 as mine {
  unalias mine;
  static int inner_value(void) { return mine; }
  alias 3 as mine {
    static int nested_value(void) { return mine; }
    unalias mine;
    static int revealed_value(void) { return mine; }
  }
}

alias 8 as own {
  unalias own;
  static int own_value(void) { return own; }
}

typedef struct Sized {
  alias 4 as mine;
  int wide[mine];
  unalias mine;
  int narrow[mine];
  alias 5 as mine {
    unalias mine;
    int wrapped[mine];
  }
} Sized;

enum Levels {
  alias 20 as mine;
  TWENTY = mine,
  unalias mine;
  ONE = mine
};

int main(void) {
  printf("%d %d %d %d %d %d %d %d\n", inner_value(), nested_value(),
         revealed_value(), own_value(), (int) (sizeof(Sized) / sizeof(int)),
         TWENTY, ONE, mine);
  return 0;
}
