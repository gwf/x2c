/*  import-method-form-static.x -- a call on an imported package type's
    name, `panels.Panel.label(panel, 3)`, invokes `$Panel.label`, which the
    package defines under its source name.
*/
import "panels";

#include <stdio.h>

int main(void) {
  panels.Panel panel = { 2 };
  printf("%d %d\n", panels.Panel.label(panel, 3), panel.label(3));
  return 0;
}
