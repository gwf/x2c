#include "x2c.x"

meta static List number_rows(void) => %(42);

macro Entry $invalid_rows() {
  @number_rows()
}

Map values = %{ $($invalid_rows()) };
