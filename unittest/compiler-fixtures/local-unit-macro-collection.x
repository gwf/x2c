// Collection tries a Unit macro defined in the same file, so a caller
// before the invocation sees the generated method and its return type. A
// macro whose signature reads top-level Lisp fails that attempt, keeps
// nothing, and still expands in the full parse.
#include "x2c.x"

macro Unit $scale(Type $type, Name $method, Name $label, Expr $factor) {
  $type $type.$method($type value) { return value * $factor; }
  String $label($type value) { return %"$value"; }
}

static int early(void) {
  int n = 21;
  return n.twice() + twice_label(n).len();
}

$scale(int, twice, twice_label, 2);

$(def local_name "thrice")

macro Unit $named(Type $type) {
  $type $(x2c.ident local_name)($type value) { return value * 3; }
}

$named(int);

int main(void) {
  printf("%d %d\n", early(), thrice(2));
  return 0;
}
