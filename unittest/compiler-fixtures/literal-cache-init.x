#include "x2c.x"

static String path = %"$root/child";
static String root = %"root";
static List values = %(alpha $root $path);
static Array positions = %[$root, $path];
static Map lookup = %{root: $root, path: $path};
static Var boxed_string = %"box:$path";
static Var boxed_list = %(boxed $root);
static Var boxed_array = %[$path];
static Var boxed_map = %{path: $path};

int main(void) {
  printf("%s\n", path);
  printf("%s\n", values.repr());
  printf("%s\n", positions.repr());
  printf("%s\n", lookup.repr());
  printf("%s\n", boxed_string.string());
  printf("%s\n", boxed_list.list().repr());
  printf("%s\n", boxed_array.array().repr());
  printf("%s\n", boxed_map.map().repr());
  return 0;
}
