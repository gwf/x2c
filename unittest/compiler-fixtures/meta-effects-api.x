#include "x2c.x"
#include "meta.x"

/* Project meta code contributes effects through `lib/meta.x` calls: one
   fresh name that two quotations share, a declaration the unit holds once
   per key, and a statement the file initialization runs. */
static int total = 0;

meta static List swapped(List a, List b) {
  Atom saved = x2c_fresh_name("saved");
  List keep = $!{ int $saved = $a; };
  return x2c_code(
    $!{ { $keep $a = $b; $b = $saved; } }, %(${x2c_effect_name(saved)}));
}
macro Stmt $swap(Expr $a, Expr $b) { @swapped($a, $b) }

/* Every use names the one `static int` declared under the key "count". */
meta static List counter(Atom count) => %(
  ${x2c_effect_name(count)}
  ${x2c_effect_support("count", count, $!Unit{ static int $count; })});

meta static List counted(List amount) {
  Atom count = x2c_fresh_name("count");
  return x2c_code(
    $!{ $count += $amount; },
    %(@{counter(count)}
      ${x2c_effect_initialize(<finish>, $!{ total += $amount; })}));
}
macro Stmt $count(Expr $amount) { @counted($amount) }

meta static List count_read(void) {
  Atom count = x2c_fresh_name("count");
  return x2c_code($!( $count ), counter(count));
}
macro Expression $count_value() => $count_read();

int main(void) {
  int saved = 1, other = 2;
  $swap(saved, other);
  $count(2);
  $count(40);
  printf("%d %d %d %d\n", saved, other, $count_value(), total);
  return 0;
}
