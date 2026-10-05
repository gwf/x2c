#include "x2c.x"
#include "meta.x"

/* File-scope constant expressions call a `meta` function the unit defines,
   which collection evaluates before the full parse. */

meta static int thirty(void) => 30;
meta int twice(int n) => n * 2;

enum { Plain = $thirty() };
typedef enum Color { First = $twice(5), Second } Color;
int table[$thirty()];
struct Row { int cells[$twice(2)]; };

int main(void) {
  printf("%d %d %d\n", Plain, First, Second);
  printf("%d %d\n", (int) (sizeof table / sizeof table[0]),
    (int) (sizeof(struct Row) / sizeof(int)));
  return 0;
}
