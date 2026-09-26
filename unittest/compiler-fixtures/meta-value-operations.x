/* Value operations use the same native strings and interpreted callbacks. */
#include "x2c.x"

$(import "meta-value-operations.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  String source = " ..ready.. ";
  String whitespace = " \tready\n";
  printf("strip %s %s\n", $(trim_chars " ..ready.. "), trim_chars(source));
  printf("space %s %s\n", $(trim_space " \tready\n"), trim_space(whitespace));
  printf("map %d %d\n", $(mapped_values 4), mapped_values(argc + 3));
  printf("empty %d %d\n", $(mapped_empty 0), mapped_empty(argc - 1));
  return 0;
}
