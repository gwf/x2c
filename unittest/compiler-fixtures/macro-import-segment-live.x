$(import "macro-import-segment-family.xmacro")
#include "x2c.x"

$project.imports.segment(imported_segment_answer);

int main(void) {
  printf("%d\n", imported_segment_answer());
  return 0;
}
