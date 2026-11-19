#include "system-macros.x"

/* A region frees mutable allocations together. Canonical text belongs to a
   pool, normally lasting until shutdown. Containers do not adopt
   references. */
static String make_label(void) {
  auto {
    Buffer out = Buffer.new();
    out.write("ready").write("!");
    return out; // The String conversion interns text before the region ends.
  }
  return NULL;
}

int main(void) {
  puts(%"Label: $(make_label())");
  Scope saved = auto Scope.new();
  Array kept;
  auto {
    Array temporary = [1, 2];
    temporary.move_to(&saved); // Preserve the container beyond this region.
    kept = temporary;
  }
  puts(%"Retained array: $(kept.repr())");
  int level = 1;
  with (level = 9) {
    puts(%"Temporary level: $level");
  }
  alias kept[0] as first;
  first += 4; // An alias substitutes its expression on each use.
  puts($dedent(%"
    Restored level: $level
    Aliased element: $(kept[0])"));
  try {
    defer puts("Cleanup before catch");
    raise %(bad-arg (operation "tour"));
  }
  catch %(bad-arg *details): puts("Caught bad-arg");
  finally puts("Finally");
  return 0;
}
