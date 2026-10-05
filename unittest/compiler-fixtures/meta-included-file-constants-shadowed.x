// An included file's file-scope constants call the `meta` function it
// defines, not the same-named one this unit defines after the include.
#include "x2c.x"
#include "meta-included-file-constants/cells.x"

meta static int thirty(void) => 31;
int meta_cells_own[$thirty()];

int main(void) { return 0; }
