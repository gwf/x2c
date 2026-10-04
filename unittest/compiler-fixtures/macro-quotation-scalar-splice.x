#include "x2c.x"
#include "meta.x"

/* Each number or String a spliced data List holds becomes its literal,
   with the width, signedness, and precision of its value, in a typed
   quotation too. A macro value applied to one such List takes it as the
   whole sequence. */
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

static long sum3(long a, long b, long c) => a + b + c;

meta static List typed_sum(List unused) {
  List xs = %(1 2 3);
  return $!long{ sum3($xs...) };
}

meta static List typed_sizes(List unused) {
  List xs = %(4 5);
  return $!(int *){ (int[]){ $xs... } };
}

meta static List typed_symbol(List unused) {
  List xs = %(<wanted>);
  return $!String{ Symbol_str($xs...) };
}

macro Expression $add(Expr $xs...) => sum3($xs...);
macro Stmt $show(Expr $xs...) { printf("[%s]\n", $xs...); }

meta static List applied_sum(List unused) {
  Macro add = $add;
  return add(%(1 2 3));
}

meta static List applied_show(void) {
  Macro show = $show;
  return %(${show(%("label"))});
}

macro Expression $call_of(Expr $v) => $call($v);
macro Expression $typed_sum_of(Expr $v) => $typed_sum($v);
macro Expression $typed_sizes_of(Expr $v) => $typed_sizes($v);
macro Expression $typed_symbol_of(Expr $v) => $typed_symbol($v);
macro Expression $applied_sum_of(Expr $v) => $applied_sum($v);
macro Stmt $applied_show_of() { $applied_show()... }
macro Expression $numbers_of(Expr $v) => $numbers($v);
macro Expression $words_of(Expr $v) => $words($v);

int main(void) {
  (void) $call_of(0);
  Array n = $numbers_of(0), w = $words_of(0);
  printf("%s %s\n", n.repr().str(), w.repr().str());
  Symbol wanted = <other>;
  char *label = "the variable";
  int *sizes = $typed_sizes_of(0);
  printf("%ld %d %d %s %ld\n", $typed_sum_of(0), sizes[0], sizes[1],
         $typed_symbol_of(0), $applied_sum_of(0));
  (void) wanted;
  (void) label;
  $applied_show_of();
  return 0;
}
