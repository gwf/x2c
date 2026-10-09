#include "rewrite.x"

macro Expression $store_probe(Expr $base, Expr $key, Expr $value) =>
  $base[$key] = $value;
macro Expression $update_probe(Expr $base, Expr $key, Expr $value) =>
  $base[$key] += $value;

$rewrite($store_probe, $!Array{${%(!and ?base)}}, <?key>, <?value>)
$rewrite($update_probe, $!Array{${%(!and ?base)}}, <?key>, <?value>)
meta Code first_probe(Code code) {
  (void) code;
  return $!Var{ int_var(99) };
}

$rewrite($store_probe, $!Array{${%(!and ?base)}}, <?key>, <?value>)
$rewrite($update_probe, $!Array{${%(!and ?base)}}, <?key>, <?value>)
meta Code second_probe(Code code) {
  (void) code;
  return $!Var{ int_var(88) };
}

int main(void) {
  Array values = [1];
  Map counts = {};
  Var stored = (values[0] = 10);
  Var updated = (values[0] += 2);
  Var fallback_store = (counts[<key>] = 10);
  Var fallback_update = (counts[<key>] += 2);
  printf("%ld %ld %ld %ld %ld %ld\n", stored.integer(), updated.integer(),
    values[0].integer(), fallback_store.integer(), fallback_update.integer(),
    counts[<key>].integer());
  return stored.integer() != 99 || updated.integer() != 99 ||
    values[0].integer() != 1 || fallback_store.integer() != 10 ||
    fallback_update.integer() != 12 || counts[<key>].integer() != 12;
}
