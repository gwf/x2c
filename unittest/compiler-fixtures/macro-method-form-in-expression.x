/* A method-form decorator applies only to a whole expression statement.
   Inside a larger expression the call is an ordinary method call. */

typedef struct Ui { int base; } Ui;

macro Decorator $Ui.row(Stmt $body, Expr $ui, Expr $gap) {
  $body
}

int main(void) {
  Ui ui = { 1 };
  int k = 0;
  k = ui.row (1) { }
  return k;
}
