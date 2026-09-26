#include <stdio.h>

typedef int native;

/* A native definition is an ordinary runtime function, so its body may use
   forms a lowered `meta` body declines, such as a function-local static. */
meta native int next_ticket(void) {
  static int ticket = 40;
  return ++ticket;
}

$(import "meta-native-definition.xmacro")

int main(void) {
  next_ticket();
  printf("%d %d %d\n", next_ticket(), twice(4), $twice(5));
  return 0;
}
