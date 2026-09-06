#include "x2c.x"
#include <stdio.h>

static int value_calls;
static int tag_calls;

static Var next_value(void) {
  value_calls++;
  return 7;
}


static Symbol next_other_tag(void) {
  tag_calls++;
  return <f64>;
}


int main(void) {
  Var value = 7, absent = void;
  Symbol other_tag = <f64>;
  int is = 1, not = 1;

  int ok =
    next_value() is not double && value_calls == 1 &&
    value is /* contextual sequence */ not <f64> &&
    value is not other_tag &&
    value is not next_other_tag() && tag_calls == 1 &&
    value is not void && absent is not int &&
    value is not double == 1 && is && not;

  printf("%d %d %d\n", ok, value_calls, tag_calls);
  return ok ? 0 : 1;
}
