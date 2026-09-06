#include "x2c.x"

static int order = 0;

static void record_step(int value) {
  order = order * 10 + value;
}

/* A continue only re-enters the enclosing loop, so it must not pop the
   transfer frame of a try that encloses that loop.  A later raise in the
   same try still has to reach the catch. */
static int continue_inside_try(void) {
  int caught = 0;
  try {
    for (int i = 0; i < 3; i++) {
      if (i == 0) continue;
      if (i == 1) raise %(invariant);
    }
  }
  catch %(invariant): {
    caught = 1;
  }
  return caught;
}

/* A break only leaves the switch, so a function-scope defer must still run
   at function exit rather than at the break. */
static void break_inside_switch(void) {
  order = 0;
  defer record_step(2);
  int selector = 1;
  switch (selector) {
    case 1:
      record_step(1);
      break;
    default:
      break;
  }
  record_step(3);
}

/* foreach lowers to a while loop, so its continue needs the same boundary
   as a plain for loop. */
static int continue_inside_foreach(void) {
  int caught = 0;
  try {
    foreach(Var item, %( 1 2 3 )) {
      if (item.int() == 1) continue;
      if (item.int() == 2) raise %(invariant);
    }
  }
  catch %(invariant): {
    caught = 1;
  }
  return caught;
}

/* break and continue need separate barriers.  A continue inside a switch
   targets the enclosing loop, so it must still run a defer registered in the
   loop body; a break in the same loop targets the switch, so it must not.
   One shared barrier gets exactly one of these two wrong. */
static void loop_switch_boundaries(void) {
  order = 0;
  for (int i = 0; i < 3; i++) {
    defer record_step(9);
    switch (i) {
      case 0:
        continue;
      default:
        break;
    }
    record_step(i);
  }
}

/* The converse nesting: a break inside a loop nested in a switch targets
   that loop, so a defer registered in the case block runs when the case
   block exits, not at the inner break. */
static void switch_loop_boundaries(void) {
  order = 0;
  int selector = 1;
  switch (selector) {
    case 1: {
      defer record_step(4);
      while (1) {
        break;
      }
      record_step(5);
      break;
    }
    default:
      break;
  }
  record_step(6);
}

int main(void) {
  int from_try = continue_inside_try();
  break_inside_switch();
  int from_switch = order, from_foreach = continue_inside_foreach();
  loop_switch_boundaries();
  int from_loop_switch = order;
  switch_loop_boundaries();
  int from_switch_loop = order;
  printf("%d %d %d %d %d\n", from_try, from_switch, from_foreach,
         from_loop_switch, from_switch_loop);
  return from_try == 1 && from_switch == 132 && from_foreach == 1
      && from_loop_switch == 91929 && from_switch_loop == 546 ? 0 : 1;
}
