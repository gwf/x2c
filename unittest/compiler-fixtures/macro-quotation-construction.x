#include "meta.x"

meta static int constructed(void) {
  List binding = x2c_binding_fresh("constructed");
  Type type = %(int);
  Code value = $!int{ 42 };
  Code actual = $!{ $type $binding = $value; };
  List expected = %("x2c.quoted" seq
    (declare $type (bindings (op = (bind $binding ()) $value))));
  if (actual !== expected)
    x2c_diagnostic_fail("quotation must insert supplied syntax immediately", NULL);

  type = %(* int);
  actual = $!{ $type $binding; };
  expected = %("x2c.quoted" seq
    (declare (int) (bindings (bind $binding (*)))));
  if (actual !== expected)
    x2c_diagnostic_fail("quotation must normalize a supplied pointer type", NULL);

  type = %(int);
  value = Code.lowered($!int{ 42 }, NULL);
  actual = $!{ $type $binding = $value; };
  expected = %("x2c.quoted" seq
    (declare $type (bindings (op = (bind $binding ()) $value))));
  if (actual !== expected)
    x2c_diagnostic_fail("quotation must preserve the supplied stage", NULL);
  return 1;
}

meta static Code finished(void) {
  Code value = Code.lowered($!int{ 41 }, NULL);
  return $!( $value + 1 );
}

meta static Code sourced(void) {
  Code name = x2c_ident("answer");
  Code value = %(src (source "<constructed>" 0 6) $name);
  return $!( $value + 1 );
}

int main(void) {
  int answer = 41;
  if ($constructed() != 1 || $finished() != 42 || $sourced() != 42) return 1;
  puts("quotation construction preserves syntax, stages and placement");
  return 0;
}
