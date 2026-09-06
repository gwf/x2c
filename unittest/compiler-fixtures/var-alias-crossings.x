#include "x2c.x"

typedef Var Dynamic;
typedef Dynamic DynamicAlias;

static int pass_calls;
static int take_calls;

static DynamicAlias make_alias(long value) {
  return value;
}

static DynamicAlias pass_alias(Dynamic value) {
  pass_calls++;
  return value;
}

static long take_alias(DynamicAlias value) {
  take_calls++;
  return value;
}

int main(void) {
  long precise = 9007199254740993L;
  Dynamic initialized = precise;
  DynamicAlias assigned = 0;
  assigned = precise + 1;
  DynamicAlias argument = pass_alias(precise), returned = make_alias(precise);
  long direct = returned, through = take_alias(initialized);

  printf("crossings=%d,%d,%d,%d,%d,%d calls=%d\n",
         initialized == precise, assigned == precise + 1,
         argument == precise, returned == precise,
         direct == precise, through == precise, pass_calls + take_calls);
  printf("compare=%d,%d,%d,%d,%d,%d,%d,%d mixed=%d,%d\n",
         returned == initialized, returned != assigned,
         returned === initialized, returned !== initialized,
         returned < assigned, returned <= initialized,
         assigned > returned, initialized >= returned,
         argument == precise, precise < assigned);
  return 0;
}
