#include "x2c.x"

int macro_offset = 3;

macro Expression $project.math.increment($value) => ($value + 1)
macro Expression $double_increment($value) => (
  $project.math.increment($project.math.increment($value))
)
macro Expression $with_offset($value) => ($value + macro_offset)

int main(void) {
  int macro_offset = 100, value = 5;
  printf(
    "%d %d\n",
    $double_increment(value),
    $with_offset(value)
  );
  return 0;
}
