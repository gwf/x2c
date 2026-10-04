#include "x2c.x"
$(import "macro-import-string-add.xmacro")

/* A declaration produced during collection lets the full parse reuse the
   import that collection read, so collection resolves its String `+`. */
macro Declaration $declare_count(Name $name) { int $name; }
$declare_count(count);

int main(void) {
  $greet();
  printf("%d\n", count);
  return 0;
}
