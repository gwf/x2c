// A delivered macro that collides with a visible one is an error, as the
// includer's own import of the file would be.
macro Expression $m.value() => 8;

#include "macro-export-lib.x"

int value = $m.value();
