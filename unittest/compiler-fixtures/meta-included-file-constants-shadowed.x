// An included file's file-scope constants call the `meta` function it
// defines, not the same-named one this unit defines after the include.
#include "x2c.x"
#include "meta-included-file-constants/cells.x"
#include "meta-included-file-constants/imported-cells.x"

meta static int thirty(void) => 31;
int meta_cells_own[$thirty()];
meta static int forty(void) => 41;
int meta_cells_own_imported[$forty()];

int main(void) { return 0; }
