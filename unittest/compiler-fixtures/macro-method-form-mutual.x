/* Two Expression macros whose templates use each other's method form
   recurse, and the ordinary expansion depth limit reports it. */

#include "x2c.x"

typedef struct Pen { int ink; } Pen;

static int Pen.dot(Pen pen, int n) => n + 1;
static int Pen.dash(Pen pen, int n) => n + 2;

macro Expression $Pen.dot(Expr $pen, Expr $n) => $pen.dash($n) * 10;
macro Expression $Pen.dash(Expr $pen, Expr $n) => $pen.dot($n) * 100;

int main(void) {
  Pen pen = {};
  return pen.dot(1);
}
