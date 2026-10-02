#include "x2c.x"

static int calls;
static Var shadowed(List value) { calls++; return value; }

static void selected(void) {
  Var (*List_var)(List) = shadowed;
  try { raise %(probe (detail (nested 3))); }
  catch %(probe (detail ${List_var(%(nested 3))})): {}
}

int main(void) {
  selected(); selected();
  printf("%d\n", calls);
  return calls != 2;
}
