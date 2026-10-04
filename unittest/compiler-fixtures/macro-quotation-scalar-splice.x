#include "x2c.x"
#include "meta.x"

/* Each number or String a spliced data List holds becomes its literal,
   with the width, signedness, and precision of its value. */
static void show(unsigned a, long b, double c) {
  printf("%u %ld %.17g\n", a, b, c);
}

meta static List call(List unused) {
  unsigned u = 4000000000u;
  long b = -5000000000;
  List xs = %($u $b 1e-9);
  return $!( show($xs...) );
}

meta static List numbers(List unused) {
  List xs = %(1 2 3);
  return $!( %[$xs...] );
}

meta static List words(List unused) {
  List xs = %("a" "b");
  return $!( %[$xs...] );
}

macro Expression $call_of(Expr $v) => $call($v);
macro Expression $numbers_of(Expr $v) => $numbers($v);
macro Expression $words_of(Expr $v) => $words($v);

int main(void) {
  (void) $call_of(0);
  Array n = $numbers_of(0), w = $words_of(0);
  printf("%s %s\n", n.repr().str(), w.repr().str());
  return 0;
}
