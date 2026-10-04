// A package import in an included file loads the package's macro pack,
// whose `meta` body uses `foreach`, and the includer receives it.
#include "import-package-pack-included/provider.x"

int six = $tally.six();
