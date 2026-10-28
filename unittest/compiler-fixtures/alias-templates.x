/*  alias-templates.x -- aliases a macro template declares

    A template's alias belongs to the template: its uses substitute when
    the template is read, and its name does not capture a caller's name of
    the same spelling. A template may also write `with`.
*/

#include "x2c.x"

typedef struct Point { int x, y; } Point;

macro Stmt $set_x(Expr $target, Expr $value) {
  alias t to $target;
  t.x = $value;
}

macro Stmt $bump(Expr $target) {
  alias $target {
    _.y += 1;
    with (_.x = 100) {
      printf("inside %d\n", _.x);
    }
  }
}

macro Unit $reader(Name $name, Expr $source) {
  alias source to $source;
  int $name(void) { return source; }
}

int total = 41;
$reader(read_total, total + 1);

int main(void) {
  Point point = { 0, 0 };
  int t = 5;
  $set_x(point, t);
  $bump(point);
  printf("%d %d %d\n", point.x, point.y, read_total());
  return 0;
}
