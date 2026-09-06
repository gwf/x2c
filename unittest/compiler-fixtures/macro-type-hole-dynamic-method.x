#include "x2c.x"
#include <stdio.h>

typedef int MacroDynamicOwner;

macro Unit $dynamic(Type $type, Name $method) => {
  inline Var $type.$method($type value) {
    return Var.new(<i32>, value);
  }
}

macro Unit $literal_owner(Name $method) => {
  inline Var MacroDynamicOwner.$method(MacroDynamicOwner value) {
    return Var.new(<i32>, value);
  }
}

$dynamic(MacroDynamicOwner, var);
$literal_owner(box);

int main(void) {
  Var value = ((MacroDynamicOwner) 42).var();
  Var boxed = ((MacroDynamicOwner) 43).box();
  printf("%d %d\n", value.int(), boxed.int());
  return value.int() == 42 && boxed.int() == 43 ? 0 : 1;
}
