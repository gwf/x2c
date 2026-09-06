#include "x2c.x"

$(import "macro-import-defs.xmacro")
$(import "macro-import-helper.xlisp")
$(import "macro-import-helper.xlisp")
$(import "macro-import-defs.xmacro")

int main(void) {
  printf(
    "%d\n",
    $project.imports.increment($(+ imported-answer 0))
  );
  return 0;
}
