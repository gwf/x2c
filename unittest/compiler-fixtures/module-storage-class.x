/* `module` declarations in one member are static for the whole unit: a
   later member and the entry use them, and the interface publishes none. */
#include <stdio.h>

module {
  "module-storage-class/first.x",
  "module-storage-class/second.x",
}

int main(void) {
  tally_node node = { 4 };
  tally_add(node);
  printf("%d %d\n", tally_total, tally_twice());
  return 0;
}
