#include "x2c.x"
#include "meta.x"

// A name value and an untyped quotation have the type of what the name
// refers to where the expansion stands.
static int twice(int value) => value * 2;

meta static List spelled(String name) {
  List function = x2c_ident(name);
  Type direct = Code.type(function), quoted = Code.type($!( $function ));
  return $!( $(%"$(direct.repr()) $(quoted.repr())") );
}

macro Expression $signature_of(Literal $name) => $spelled($name);

int main(void) {
  double scale = 1.5;
  puts($signature_of("twice"));
  puts($signature_of("scale"));
  return twice(0);
}
