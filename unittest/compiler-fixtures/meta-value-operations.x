/* Value operations use the same native strings and interpreted callbacks. */
#include "x2c.x"

meta static String trim_chars(String text) => text.strip(" .");

meta static String trim_space(String text) {
  return text.strip((char *) 0);
}

meta static int mapped_values(int offset) {
  Array input = [1, 2, 3];
  Func add = %!(value) => value + offset;
  Array output = input.map(add);
  return (int) output[0] * 100 + (int) output[1] * 10 + (int) output[2];
}

meta static int mapped_empty(int n) {
  Array input = [];
  Func unused = %!(value) => value + n;
  Array output = input.map(unused);
  output.push(7);
  return (int) input.len() * 10 + (int) output.len();
}

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
