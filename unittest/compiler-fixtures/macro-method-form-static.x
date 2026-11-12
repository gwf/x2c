/* A call on a type name, `T.name(arguments)`, invokes the macro `$T.name`
   with the arguments unchanged, as `$T.name(arguments)` does: Entry rows,
   a method reached as `r.m(x)` and as `T.m(r, x)`, inside other templates
   with and without a hole argument, and a decorator at the start of a
   statement. In its own template the call is the function, and a call
   with no such macro stays an ordinary call. */

#include "x2c.x"

typedef struct Desc { int width, height; } Desc;
typedef struct Win { int area; } *Win;

static Win Win.open(Desc desc) {
  Win w = xmalloc(sizeof *w);
  w.area = desc.width * desc.height;
  return w;
}

static Desc desc_of(Map @options) => (Desc){
  options.getdefault(<width>, 1).integer(),
  options.getdefault(<height>, 1).integer() };

macro Expression $Win.open(Entry @options) =>
  Win.open(desc_of(@options));

typedef struct Ui { int base; } Ui;

static int Ui.button(Ui ui, String label) =>
  printf("[%s %d]\n", label, ui.base);
static int Ui.plain(Ui ui, int n) => ui.base + n;

macro Expression $Ui.button(Expr $ui, Expr $label) =>
  $ui.button($label) * 10;

macro Expression $square(Expr $side) =>
  Win.open(width: $side, height: $side);
macro Expression $unit_win() => Win.open(width: 1, height: 1);

macro Decorator $Ui.row(Stmt $body, Expr $ui) {
  {
    printf("row %d\n", ($ui).base);
    $body
  }
}

int main(void) {
  Win w = Win.open(width: 3, height: 4);
  printf("%d %d %d\n", w.area, $square(5).area, $unit_win().area);
  Ui ui = { 7 };
  int a = ui.button("r"), b = Ui.button(ui, "T");
  printf("%d %d %d\n", a, b, Ui.plain(ui, 1));
  Ui.row(ui) printf("type-name decorator\n");
  return 0;
}
