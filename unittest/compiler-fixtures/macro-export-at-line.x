// The includer receives an exported import at its include line, so source
// above the include cannot use it.
#include "x2c.x"

int early = $m.value();

#include "macro-export-lib.x"
