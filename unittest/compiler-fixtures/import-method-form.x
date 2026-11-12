/*  import-method-form.x -- consumer of the panels toy package.

    `panels.Panel` is `panels__Panel` in generated C; its method-form macros
    are found by the source name `$Panel.NAME`, in source and in a template
    whose receiver is a hole.
*/
import "panels";

#include <stdio.h>

macro Stmt $show(Expr $panel) {
  $panel.section() printf("%d\n", $panel.label(4));
}

int main(void) {
  panels.Panel panel = { 2 };
  panel.section() printf("%d\n", panel.label(3));
  $show(panel);
  return 0;
}
