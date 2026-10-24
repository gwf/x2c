/*  alias-scopes.x -- lexical aliases at each scope that permits them

    Each use substitutes the parsed expression: an unused alias evaluates
    nothing, and repeated uses evaluate it again. The expression keeps the
    bindings it had at the declaration when a later declaration hides one
    of its names. Aggregate, enumerator, and wrapper bodies end their
    aliases at the closing brace, while the declarations they wrap keep
    their ordinary placement.
*/

#include "x2c.x"

typedef struct Settings { int width, height; } Settings;
typedef struct Owner { Settings settings; int count; } Owner;

static Owner owner = { { 3, 4 }, 0 };
static int evaluations;

static Owner *counted(void) {
  evaluations++;
  return &owner;
}

alias owner.settings as shared;
alias counted()->count as tally;

enum { BASE = 10 };

enum Kinds {
  alias BASE + 1 as first;
  ONE = first,
  alias BASE * 2 { TWO = _, THREE, }
  FOUR
};

typedef struct Grid {
  alias 3 as side;
  int cells[side * side];
  alias 4 { int extra[_]; }
} Grid;

alias owner.settings as wrapped {
  static int area(void) { return wrapped.width * wrapped.height; }
  static int parameter(int wrapped) { return wrapped; }
}

static int wrapped = 50;

int main(void) {
  Owner local = { { 1, 2 }, 0 };
  alias local.settings as settings;
  settings.width = 5;
  alias local.settings {
    _.height = 6;
    printf("braced %d %d\n", _.width, _.height);
  }

  alias counted() as unused;
  tally += 1;
  tally += 1;
  printf("tally %d evaluations %d\n", owner.count, evaluations);
  printf("shared %d area %d parameter %d wrapped %d\n",
         shared.height, area(), parameter(9), wrapped);
  printf("enum %d %d %d %d grid %d\n", ONE, TWO, THREE, FOUR,
         (int) (sizeof(Grid) / sizeof(int)));

  {
    int settings = 42;
    printf("shadowed %d\n", settings);
  }
  alias settings.width as width;
  alias width as again;
  again = 8;
  printf("chain %d\n", local.settings.width);

  int x = 1;
  alias x as y;
  {
    int x = 2;
    y = y + 10;
    printf("hidden %d %d\n", x, y);
  }
  printf("kept %d\n", x);

  int alias = 3;
  alias += 1;
  printf("identifier %d\n", alias);
  return 0;
}
