#include "x2c.x"

class Path String;
typedef String Name;

static long path_length(Path path) { return path.len(); }
static long name_length(Name name) { return name.len(); }
static Path default_path(void) { return "build"; }
static Name default_name(void) { return "main"; }

int main(void) {
  Path path = "src";
  Name name = "parse";
  Path assigned;
  Name renamed;
  assigned = "lib";
  renamed = "tokenizer";
  printf("%ld %ld %ld %ld\n", (long) path.len(), (long) name.len(),
         (long) assigned.len(), (long) renamed.len());
  printf("%s %s\n", %"$path/$name.x", %"$assigned/$renamed.x");
  printf("%ld %ld\n", path_length("unittest"), name_length("fixture"));
  Path built = default_path();
  Name main_name = default_name();
  printf("%ld %s/%s\n", (long) built.len(), built, %"$main_name.o");
  printf("%d %d\n", path == "src", name == "parse");
  return 0;
}
