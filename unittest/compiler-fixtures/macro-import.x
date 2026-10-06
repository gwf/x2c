#include "x2c.x"

#include "macro-import-defs.x"
$(import "macro-import-helper.xlisp")
$(import "macro-import-helper.xlisp")
#include "macro-import-defs.x"

int main(void) {
  printf(
    "%d\n",
    $project.imports.increment($(+ imported-answer 0))
  );
  return 0;
}
