#include "x2c.x"

/* `%"`, `%[`, and `%<<` open literals even after a `)`, so a cast can
   precede them. `%(` after a `)` stays modulo; parenthesize the literal. */

typedef String Path;

static Path join(String base, String name) {
  return (Path) %"$base/$name";
}

int main(void) {
  String path = join(%"build", %"x2c");
  Array words = (Array) %[one, two];
  SymbolSet flags = (SymbolSet) %<<quiet verbose>>;
  List command = (List) (%(echo done));
  printf("%s\n", path);
  printf("%s %zu\n", words.repr(), flags.len());
  printf("%s\n", command.repr());
  return 0;
}
