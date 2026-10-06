// Relative includes resolve beside their source file across collection modes.
#include "macro-import-relative/plain.x"
#include "macro-import-relative/exported.x"

int value = $relative.value();
