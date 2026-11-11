/* Method forms inside templates. A receiver that is a hole, a hole-typed
   local, or a typed expression invokes the type's decorator or Expression
   macro where the template expands. Only a call written in `$T.name`'s own
   template is the method, so a wrapper calls the method it shadows, and
   the same decorator nests in a template, in its own target, and in
   source. */

#include "x2c.x"

// A Ui is a handle: copies share one nesting depth.
typedef struct Ui { int *depth; } Ui;

static int Ui.say(Ui ui, String text) =>
  printf("%*s%s\n", *ui.depth * 2, "", text);

static int Ui.button(Ui ui, String label) {
  printf("%*s[%s]\n", *ui.depth * 2, "", label);
  return 1;
}

macro Decorator $Ui.row(Stmt $body, Expr $ui, Expr $label) {
  {
    Ui row = $ui;
    row.say($label);
    (*row.depth)++;
    $body
    (*row.depth)--;
  }
}

macro Expression $Ui.button(Expr $ui, Expr $label) =>
  $ui.button($label) * 10;

// A hole receiver, in decorator and expression form.
macro Stmt $toolbar(Expr $ui) {
  $ui.row ("toolbar") {
    printf("%d\n", $ui.button("a"));
  }
}

// A hole-typed local receiver.
macro Stmt $panel(Expr $ui) {
  Ui local = $ui;
  local.row ("panel") printf("%d\n", local.button("b"));
}

// A method-form decorator whose template nests another one.
macro Decorator $Ui.card(Stmt $body, Expr $ui) {
  $ui.row ("outer") {
    $ui.row ("inner") $body
  }
}

// The same decorator nested in one template.
macro Stmt $twice(Expr $ui) {
  $ui.row ("a") {
    $ui.row ("b") { $ui.say("leaf"); }
  }
}

typedef struct Pen { int ink; } Pen;

static int Pen.dot(Pen pen, int n) => n + 1;
static int Pen.dash(Pen pen, int n) => n + 2;

// `$Pen.dot` uses the macro `$Pen.dash`, which calls its own method.
macro Expression $Pen.dot(Expr $pen, Expr $n) => $pen.dash($n) * 10;
macro Expression $Pen.dash(Expr $pen, Expr $n) => $pen.dash($n) * 100;

int main(void) {
  int depth = 0;
  Ui ui = { &depth };
  $toolbar(ui);
  $panel(ui);
  ui.card() { ui.card() ui.say("deep"); }
  $twice(ui);
  ui.row ("s1") { ui.row ("s2") { $twice(ui); } }
  Pen pen = {};
  printf("%d %d\n", pen.dot(1), pen.dash(1));
  return 0;
}
