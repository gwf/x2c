#include "x2c.x"

class Name String;
typedef String Label;

/* A C string beside an alias of String converts to String, so `+`
   concatenates through String.add rather than adding C pointers. */
int main(void) {
  Name name = String.new("build");
  Label label = String.new("main");
  String text = ".c";
  char *suffix = ".h", *prefix = "include/";
  const char *extension = ".x";
  String object = name + ".o", source = "src/" + label;
  printf("%s %s\n", object, source);
  printf("%s %s\n", label + suffix, prefix + name);
  printf("%s %s\n", name + text, name + "/" + label + text);
  printf("%s %s\n", text + extension, extension + label);
  name += ".d";
  printf("%s\n", name);
  return 0;
}
