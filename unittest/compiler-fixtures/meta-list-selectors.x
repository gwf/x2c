/* Optional compound selectors have matching native and meta behavior. */
#include "x2c.x"
#include "list-selectors.x"

$(import "meta-list-selectors.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $list_compound_selectors(0),
    list_compound_selectors(argc - 1));
  printf("%d %d\n", $var_compound_selectors(0),
    var_compound_selectors(argc - 1));
  return 0;
}
