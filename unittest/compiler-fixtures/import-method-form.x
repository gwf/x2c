/*  import-method-form.x -- consumer of the panels toy package.

    `panels.Panel` is `panels__Panel` in generated C; its method-form macros
    are found by the source name `$Panel.NAME`.
*/
import "panels";

#include <stdio.h>

int main(void) {
  panels.Panel panel = { 2 };
  panel.section() printf("%d\n", panel.label(3));
  return 0;
}
