#include "x2c.x"
#include "meta.x"

/* A typed quotation lifts a hole's value as an untyped quotation does:
   every number exactly in its own type, and a String typed `String` as a
   String literal. An `x2c_ident` in a member position is its spelling,
   and one that declares is the name it declares. */

typedef struct Point { int x, y; } Point;

meta static List big_unsigned_code(List zero) {
  unsigned u = 4000000000u;
  return $!unsigned{ $u + $zero };
}
meta static List big_negative_code(List zero) {
  long n = -5000000000;
  return $!long{ $n + $zero };
}
meta static List tenths_code(List count) {
  double tenth = 0.1;
  return $!double{ $tenth * $count };
}
meta static List quarter_code(void) {
  float f = 1.25f;
  return $!float{ $f };
}
meta static List widest_code(void) {
  unsigned long long all = 18446744073709551615ull;
  return $!(unsigned long long){ $all };
}
meta static List greeting_code(void) {
  String s = "hello";
  return $!String{ $s };
}
meta static List member_y_code(List object) {
  List field = x2c_ident("y");
  return $!int{ $object.$field };
}
static int answer(void) => 42;
meta static List declared_code(void) {
  List f = x2c_ident("answer"), n = x2c_ident("total");
  return $!int{ ({ extern int $f(void); int $n = $f(); $n + 1; }) };
}
macro Expression $big_unsigned(Expr $zero) => $big_unsigned_code($zero);
macro Expression $big_negative(Expr $zero) => $big_negative_code($zero);
macro Expression $tenths(Expr $count) => $tenths_code($count);
macro Expression $quarter() => $quarter_code();
macro Expression $widest() => $widest_code();
macro Expression $greeting() => $greeting_code();
macro Expression $member_y(Expr $object) => $member_y_code($object);
macro Expression $declared() => $declared_code();

int main(void) {
  printf("%u %ld\n", $big_unsigned(0), $big_negative(0));
  printf("%.17g %g\n", $tenths(3), $quarter());
  printf("%llu\n", $widest());
  String s = $greeting();
  printf("[%s] %d [%s]\n", s, s.len(), $greeting() + "!");
  Point p = {1, 2};
  printf("%d %d\n", $member_y(p), $declared());
  return 0;
}
