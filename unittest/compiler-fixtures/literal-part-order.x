#include "x2c.x"

/* x2c has no type for a native macro's expansion. */
#define BOXED(n) int_var(n)

static String trail = NULL;

static int note(String name) {
  trail = %"$trail$name";
  return trail.len();
}

static List items(String name) {
  note(name);
  return %(x);
}

int main(void) {
  trail = "";
  List inserted = %(${note("a")} ${note("b")});
  List spliced = %("w" @{items("c")} "e" @{items("d")});
  String joined = %"${note("e")}-${note("f")}";
  Array quoted = %[${note("g")}, ${note("h")}];
  Array bare = [note("i"), note("j")];
  Map keyed = %{${note("k")}: ${note("l")}};
  Map braced = {note("m"): note("n")};
  List nested = %((${note("o")}) ${note("p")});
  String name = "q";
  List stable = %($name $trail);
  List leading = %(${note("r")} $name);
  Array native = [BOXED(note("s")), note("t")];
  printf("%s %ld %ld %ld %ld %ld %ld %ld %ld %ld %ld %ld\n", (char *) trail,
         (long) inserted.len(), (long) spliced.len(), (long) joined.len(),
         (long) quoted.len(), (long) bare.len(), (long) keyed.len(),
         (long) braced.len(), (long) nested.len(), (long) stable.len(),
         (long) leading.len(), (long) native.len());
  return 0;
}
