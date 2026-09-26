/* Native and meta status cells and represented absence values agree. */
#include "x2c.x"

struct SymbolCell { Symbol value; };

$(import "meta-output-cells.xmacro")

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $output_cells(0), output_cells(argc - 1));
  printf("%d %d\n", $represented_results(0),
    represented_results(argc - 1));
  return 0;
}
