#include <stdio.h>

/* `.` on pointer arithmetic over a pointer typedef selects through the
   pointer, as it does on a variable of that typedef. */
typedef struct P { int type; } *P;
typedef P Q;
typedef union U { int type; float f; } *U;

static int before(P first) { return (first - 1).type; }
static int after(P first, int i) { return (first + i).type; }
static int offset(P first) { return (1 + first).type; }
static int indexed(P first) { return first[1].type; }
static int deref(P first) { return (*first).type; }
static int chosen(P a, P b, int which) { return (which ? a : b).type; }
static int arrow(P first) { return (first - 1)->type; }
static int chained(Q first) { return (first - 1).type; }
static int member(U first) { return (first - 1).type; }

int main(void) {
  struct P items[3] = {{7}, {9}, {11}};
  union U values[2] = {{3}, {4}};
  printf("%d %d %d\n", before(&items[1]), after(items, 2), offset(items));
  printf("%d %d %d\n", indexed(items), deref(&items[2]),
         chosen(items, &items[1], 0));
  printf("%d %d %d\n", arrow(&items[2]), chained(&items[1]),
         member(&values[1]));
  return 0;
}
