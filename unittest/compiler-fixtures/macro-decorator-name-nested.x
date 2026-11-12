/* A decorator that declares its caller's `Name` makes that name visible to
   the statements after the application, at function level, inside a plain
   block, and inside another decorator's target, including a method-form
   decorator nested in another one. */

#include "x2c.x"

macro Decorator $counted(Stmt $body, Name $result) {
  int $result = 0;
  {
    defer $result = 7;
    $body
  }
}

macro Decorator $block(Stmt $body) {
  { $body }
}

typedef struct Ui { int depth; } Ui;

macro Decorator $Ui.column(Stmt $body, Expr $ui) {
  {
    puts("column");
    $body
  }
}

macro Decorator $Ui.reorder(Stmt $body, Expr $ui, Name $changed, Expr $id) {
  int $changed = 0;
  {
    printf("reorder %s\n", $id);
    $body
    $changed = 1;
  }
}

int main(void) {
  $counted(outer) puts("level one");
  printf("%d\n", outer);
  $block() {
    $counted(inner) puts("level two");
    printf("%d\n", inner);
  }
  Ui ui = {};
  ui.column () {
    ui.reorder (changed, "tasks") { puts("rows"); }
    if (changed) puts("changed");
  }
  return 0;
}
