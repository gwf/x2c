/* A sequence hole may precede one final `Entry @rows` hole; the sequence
   takes the arguments before the first `key: value` row. One generator
   template therefore covers every arity, for Expression macros and
   decorators, in source, in the explicit spelling, and in a template. A
   sequence hole spliced as `@args` into a meta call's rest parameter
   passes each item. */

#include "x2c.x"
#include "meta.x"

typedef struct Ui { int base; } Ui;

static int Ui.sum(Ui ui, int a, Map @options) =>
  (ui.base + a) * options.getdefault(<scale>, 1).integer();
static int Ui.sum2(Ui ui, int a, int b, Map @options) =>
  (ui.base + a + b) * options.getdefault(<scale>, 1).integer();
static int Ui.zero(Ui ui, Map @options) => options.len();
static int Ui.open(Ui ui, String label, Map @options) =>
  printf("open %s %d\n", label, options.len());
static int Ui.open0(Ui ui, Map @options) =>
  printf("open0 %d\n", options.len());

macro Unit $form(Name $m) {
  macro Expression $Ui.$m(Expr $ui, Expr @args, Entry @options) =>
    $ui.$m(@args, @options);
}
$form(sum);
$form(sum2);
$form(zero);

macro Unit $block(Name $m) {
  macro Decorator $Ui.$m(Stmt $body, Expr $ui, Expr @args, Entry @options) {
    {
      $ui.$m(@args, @options);
      $body
    }
  }
}
$block(open);
$block(open0);

macro Stmt $show(Expr $ui) {
  printf("%d %d\n", $ui.sum2(1, 2, scale: 10), $ui.zero());
  $ui.open ("t", wide: 1) printf("in template\n");
}

meta int count(List @args) => args.len();
meta int count_list(List args) => args.len();

macro Expression $count_args(Expr @args, Entry @options) =>
  $count(@args) * 10 + $count_list($args);

int main(void) {
  Ui ui = { 100 };
  printf("%d %d %d %d\n", ui.sum(1), ui.sum(1, scale: 2), ui.sum2(1, 2),
         ui.zero(k: 1, j: 2));
  printf("%d\n", $Ui.sum2(ui, 4, 5, scale: 3));
  ui.open ("s") printf("source\n");
  ui.open0 (x: 1, y: 2) printf("options only\n");
  $show(ui);
  printf("%d %d %d\n", $count_args(1, 2, 3, k: 1), $count_args(k: 2),
         $count_args());
  return 0;
}
