#include "x2c.x"
#include <stdio.h>

macro Expression $macro_index_read(Expr $values, Expr $index) => (
  $values[$index]
)

macro Unit $define_generated_index_helpers(
  Name $pointer_read,
  Name $pointer_write,
  Name $array_local,
  Name $array_read,
  Name $array_write,
  Name $map_read,
  Name $map_write
) => {
  static int $pointer_read(int *values, int index) {
    return values[index];
  }

  static void $pointer_write(int *values, int index, int value) {
    values[index] = value;
  }

  static int $array_local(void) {
    int values[2] = { 3, 4 };
    values[1] = 5;
    return values[0] + values[1];
  }

  static long $array_read(Array values, int index) {
    return values[index].integer();
  }

  static void $array_write(Array values, int index, Var value) {
    values[index] = value;
  }

  static long $map_read(Map values, Var key) {
    return values[key].integer();
  }

  static void $map_write(Map values, Var key, Var value) {
    values[key] = value;
  }
}

$define_generated_index_helpers(
  generated_pointer_read,
  generated_pointer_write,
  generated_array_local,
  generated_array_read,
  generated_array_write,
  generated_map_read,
  generated_map_write
);

int main(void) {
  int native[2] = { 1, 2 };
  generated_pointer_write(native, 0, 7);

  Array array = %[1, 2];
  generated_array_write(array, 1, 8);

  Map map = %{"key": 3};
  generated_map_write(map, %"key", 9);

  printf(
    "%d %d %ld %ld %d\n",
    generated_pointer_read(native, 0),
    generated_array_local(),
    generated_array_read(array, 1),
    generated_map_read(map, %"key"),
    $macro_index_read(native, 1)
  );
  return 0;
}
