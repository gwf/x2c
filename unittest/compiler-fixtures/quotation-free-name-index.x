#include "x2c.x"
#include "meta.x"
typedef struct Person { int age; String name; } Person;
meta static List gen(Type type) {
  Array puts = [];
  foreach (List field in Type.fields(type)) {
    String member = field.car();
    puts.push($!{ result["k"] = 1; });
  }
  List items = puts.list_free();
  List fn = x2c_ident("show");
  return $!Unit{ Map $fn($type value) { Map result = {}; @items return result; } };
}
macro Unit $gen.it(Type $type) { @gen($type) }
$gen.it(Person);
int main(void) { Person p = { 42, "A" }; printf("%s\n", show(p).repr().str()); return 0; }
