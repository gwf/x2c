/*  with-assignments.x -- temporary assignments and their restoration

    Entries run from left to right, each evaluating its destination once,
    and later entries see earlier assignments. Exit restores the saved
    values in reverse order on every path: normal exit, return, loop exits,
    and a raise from the body or from a later entry's initializer.
*/

#include "x2c.x"

typedef struct State { int mode, depth; } State;

static State state = { 1, 5 };
static int places;

static int *counted(int *place) {
  places++;
  return place;
}

static void fails(void) {
  raise %(late);
}

static int nested_depth(void) => state.depth;

static int returns_inside(void) {
  with (state.mode = 9) {
    return state.mode;
  }
}

static void loop_exits(void) {
  for (int i = 0; i < 3; i++) {
    with (state.depth = i) {
      if (i == 0) continue;
      break;
    }
  }
}

int main(void) {
  with (state.mode = 2, state.depth = state.depth + 1) {
    printf("inside %d %d %d\n", state.mode, state.depth, nested_depth());
    state.depth = 100;
  }
  printf("after %d %d\n", state.mode, state.depth);

  int value = 1;
  with (*counted(&value) = 7, value = value + 1, value = value * 10) {
    printf("repeated %d places %d\n", value, places);
  }
  printf("restored %d places %d\n", value, places);

  printf("returned %d mode %d\n", returns_inside(), state.mode);
  loop_exits();
  printf("loops depth %d\n", state.depth);

  try {
    with (state.mode = 3) {
      raise %(body);
    }
  }
  catch %(body): printf("body raise mode %d\n", state.mode);

  try {
    with (state.mode = 4, state.depth = (fails(), 0)) {
      printf("unreached\n");
    }
  }
  catch %(late):
    printf("initializer raise %d %d\n", state.mode, state.depth);

  if (value == 1) with (value = 2) {
    printf("governed %d\n", value);
  }
  printf("final %d\n", value);
  return 0;
}
