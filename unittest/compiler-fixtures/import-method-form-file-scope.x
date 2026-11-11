/*  import-method-form-file-scope.x -- a file-scope method-form decorator
    whose receiver is a file-scope variable of an imported package type.

    `panels.Panel` is `panels__Panel` in generated C; the decorator is found
    by the source name `$Panel.page`.
*/
import "panels";

#include <stdio.h>
#include "meta.x"

macro Decorator $Panel.page(Function $function, Expr $panel, Expr $path) {
  printf("page %s %d\n", $path, ($panel).depth);
  @Code.body($function)
}

panels.Panel home = { 2 };

home.page ("/home")
void show_home(void) { printf("%d\n", home.label(1)); }

int main(void) {
  show_home();
  return 0;
}
