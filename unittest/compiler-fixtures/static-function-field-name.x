#include <stdio.h>

/* A field's name is not a reference to the static function that shares
   it, so the function's prototype follows the type it names. */
typedef struct State { int orders; } State;

static void orders(State &s) { printf("%d\n", s.orders); }

int main(void) {
  State s = {3};
  orders(s);
  return 0;
}
