// The file's constants call the `meta` function it keeps to itself.
meta static int thirty(void) => 30;
enum { meta_cells_limit = $thirty() };
int meta_cells_included[$thirty()];
