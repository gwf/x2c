#include "x2c.x"
#include "meta.x"
typedef struct Person { int age; String name; } Person;
meta static List gen(Type type) {
  List fn = x2c_ident("show");
  return $!Unit{ int $fn($type value) { return value.nope; } };
}
macro Unit $gen.it(Type $type) { @gen($type) }
$gen.it(Person);
int main(void) { Person p = { 42, "A" }; printf("%d\n", show(p)); return 0; }
