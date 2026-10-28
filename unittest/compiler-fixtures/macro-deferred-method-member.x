#include "x2c.x"
#include "meta.x"

typedef int Number;

macro Unit $method(Type $type, Name $member, Expr $amount) {
  int $type.$member($type value) { return value + $amount; }
}

macro Unit $integer_method(Name $member, Expr $amount) {
  int Number.$member(Number value) { return value + $amount; }
}

meta static List construct_method(Type type, String name, int amount) {
  Macro method = $method;
  return method(type, x2c_ident(name), amount);
}

meta static List named(Type type) {
  return $method(type, x2c_ident("named"), 3);
}

meta static List literal_owner(void) {
  Macro method = $integer_method;
  return method(x2c_ident("literal"), 4);
}

meta static List string_member(Type type) {
  Macro method = $method;
  return method(type, "text", 5);
}

macro Unit $methods(Type $type) {
  @construct_method($type, "deferred", 2)
  @named($type)
  @literal_owner()
  @string_member($type)
}

$methods(Number);
$method(Number, direct, 1);

int main(void) {
  Number value = 40;
  printf("%d %d %d %d %d\n", value.direct(), value.deferred(),
    value.named(), value.literal(), value.text());
  return 0;
}
