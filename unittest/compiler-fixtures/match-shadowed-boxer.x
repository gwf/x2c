#include "x2c.x"

static int calls;

static Var shadowed(List value) { calls++; return value; }

int main(void) {
  Var (*List_var)(List) = shadowed;
  List subject = %(probe (nested 3) 4);
  match (subject) case %(probe ${List_var(%(nested 3))} ?(int value)):
    if (value != 4) return 2;
  match (subject) case %(probe ${List_var(%(nested 3))} ?(int value)):
    if (value != 4) return 2;
  if (calls != 2) return 1;
  printf("shadowed boxers remain computed match patterns\n");
  return 0;
}
