#include "x2c.x"

typedef int MacroInvalidOwner;

macro Unit $box_pointer(Type $type) => {
  inline Var $type.var(MacroInvalidOwner value) {
    return Var.new(<i32>, value);
  }
}

$box_pointer(MacroInvalidOwner *);
