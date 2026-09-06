#include "x2c.x"

typedef int MacroBoxFirst;
typedef int MacroBoxSecond;

macro Unit $box(Type $type, Literal $tag) => {
  inline Var $type.var($type value) {
    return Var.new($tag, value);
  }
}

$box(MacroBoxFirst, <i32>);
$box(MacroBoxSecond, <i32>);

int main(void) {
  MacroBoxFirst first = 19;
  MacroBoxSecond second = 23;
  printf("%ld %ld\n", first.var().integer(), second.var().integer());
  return 0;
}
