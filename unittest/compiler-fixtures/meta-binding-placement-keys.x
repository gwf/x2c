#include "meta.x"

/* Binding and placement keys are independent, in either call order. */
meta List binding_first(void) {
  List name = x2c_binding_for(<first>, "helper");
  x2c_place(%(unit-support (binding first)),
    $!Unit{ static int $name(void) { return 7; } });
  return $!( $name() );
}

meta List placement_first(void) {
  List placed = x2c_ident("placed");
  x2c_place(%(unit-support (binding second)),
    $!Unit{ static int $placed(void) { return 11; } });
  List name = x2c_binding_for(<second>, "helper");
  x2c_place(%(unit-support second),
    $!Unit{ static int $name(void) { return $placed(); } });
  return $!( $name() );
}

int main(void) {
  printf("%d %d %d %d\n", $binding_first(), $binding_first(),
         $placement_first(), $placement_first());
}
