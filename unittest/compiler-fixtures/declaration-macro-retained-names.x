#include "x2c.x"

// A Declaration macro's retained initializers and function bodies read
// their names where the expansion lands: a caller's argument naming a
// file-scope object, function, or enumerator, a private template object,
// a statement-expression local, and a parameter.

macro Expression $plus(Expr $a, Expr $b) => $a + $b;
macro Declaration $arg(Name $n, Expr $v) { int $n = $v + 1; }
macro Declaration $nested(Name $n, Expr $v) { int $n = $plus($v, 1); }
macro Declaration $hidden(Name $n) { static int tmp = 3; int $n = tmp * 2; }
macro Declaration $local(Name $n, Expr $v) {
  int $n = ({ int t = $v; t + 100; });
}
macro Declaration $getter(Name $n, Expr $v) {
  int $n(int a) { return a * 100 + $v; }
}
macro Declaration $counter(Name $n) {
  static int tmp;
  int $n(void) { tmp += 3; return tmp; }
}

int base_value = 40;
int seed(void) { return 1; }
enum { RED = 4 };

$arg(from_object, base_value);
$arg(from_call, seed());
$arg(from_enum, RED);
$nested(from_nested, base_value);
$hidden(six);
$local(from_local, 1);
$getter(get_base, base_value);
$counter(count);

int main(void) {
  printf("%d %d %d %d\n", from_object, from_call, from_enum, from_nested);
  printf("%d %d %d %d\n", six, from_local, get_base(1), count());
  return 0;
}
