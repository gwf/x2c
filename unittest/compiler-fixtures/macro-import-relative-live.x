// A relative import in an included file names a file beside that file with
// live symbol collection: the host preprocessor's line markers say which
// file each region of the merged text came from.
#include "macro-import-relative/plain.x"
#include "macro-import-relative/exported.x"

int value = $relative.value();
