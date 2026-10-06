// An included public macro replaces the preceding visible definition.
macro Expression $m.value() => 8;

#include "macro-export-lib.x"

int value = $m.value();
