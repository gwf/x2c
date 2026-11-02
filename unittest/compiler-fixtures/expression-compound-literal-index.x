/*  expression-compound-literal-index.x -- a compound literal is a postfix
    expression, so an index, member, or method call after it applies to the
    whole literal.
*/
#include "x2c.x"

typedef struct Pt { int x, y; } Pt;

static int Pt.sum(Pt p) => p.x + p.y;

int main(void) {
  int second = (int[]){5, 6}[1];
  int last = (int[3]){7, 8, 9}[2];
  int element = sizeof (int[]){1, 2, 3}[0] == sizeof(int);
  printf("%d %d %d %d %d\n", second, last, element, (Pt){3, 4}.y,
         (Pt){3, 4}.sum());
  return 0;
}
