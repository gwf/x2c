#include "x2c.x"
#include <stdio.h>

int main(void) {
  Array array = %[1, 2];
  Array array_equal = %[1, 2];
  Array array_alias = array;
  Array array_unequal = %[1, 3];
  Map map = %{x: 1};
  Map map_equal = %{x: 1};
  Map map_alias = map;
  Map map_unequal = %{x: 2};
  printf(
    "%d %d %d %d %d %d %d %d %d %d %d %d\n",
    array == array_equal, array == array_alias,
    array != array_unequal,
    array === array_equal, array === array_alias,
    array !== array_unequal,
    map == map_equal, map == map_alias, map != map_unequal,
    map === map_equal, map === map_alias, map !== map_unequal
  );
  return 0;
}
