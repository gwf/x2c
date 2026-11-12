/* A statement `receiver.name(arguments) TARGET` applies the decorator
   `$T.name` of the receiver's named type, with the receiver as its first
   explicit argument. Decorators stack, and every receiver form is
   evaluated once. A call followed by `(` stays an ordinary call, and a
   statement after the target may begin with `*` or `(`. */

#include <stdio.h>

// A Ui is a handle: copies share one nesting depth.
typedef struct Ui { int *depth; } Ui;
typedef struct App { Ui ui; } App;
typedef int (*Adder)(int);

static int add_one(int n) => n + 1;

static int Ui.say(Ui ui, String text) {
  printf("%*s%s\n", *ui.depth * 2, "", text);
  return 0;
}

static Adder Ui.adder(Ui ui, int n) => add_one;

macro Decorator $Ui.row(Stmt $body, Expr $ui, Expr $gap) {
  {
    Ui row_ui = $ui;
    printf("%*srow %d {\n", *row_ui.depth * 2, "", $gap);
    (*row_ui.depth)++;
    $body
    (*row_ui.depth)--;
    printf("%*s}\n", *row_ui.depth * 2, "");
  }
}

macro Decorator $Ui.adder(Stmt $body, Expr $ui, Expr $n) {
  printf("adder decorator\n");
  $body
}

static App app;
static int calls;

static Ui ui_of(App *owner) {
  calls++;
  return owner->ui;
}

int main(void) {
  int depth = 0;
  app.ui.depth = &depth;
  App *owner = &app;
  Ui ui = app.ui;
  Ui uis[2] = { ui, ui };

  ui.row (1)
  ui.row (2) {
    ui.say("stacked");
  }
  ui_of(owner).row (3) ui.say("call");
  app.ui.row (4) ui.say("field");
  owner->ui.row (5) ui.say("arrow field");
  uis[1].row (6) ui.say("index");
  (ui_of(owner)).row (7) ui.say("parenthesized");
  printf("calls %d\n", calls);

  int *place = &depth;
  ui.row (8) { } *place = 0;
  ui.row (9) { } (*place) = 0;

  ui.say("no decorator");
  printf("%d\n", ui.adder(0)(21));
  ui.adder(0) ui.say("adder target");
  return 0;
}
