#include "x2c.x"
#include <stdio.h>

typedef struct MacroPostfixBox {
  int value;
  int (*callable)(int);
} MacroPostfixBox;

int MacroPostfixBox.bump(MacroPostfixBox box, int delta) {
  return box.value + delta;
}

static int add_one(int value) {
  return value + 1;
}

macro Expression $project.math.increment(Expr $value) => ($value + 1)

macro Expression $macro_postfix_field(Expr $box) => (
  $project.math.increment($box.value)
)

macro Expression $macro_postfix_arrow(Expr $box) => (
  $box->value
)

macro Expression $macro_postfix_method(Expr $box, Expr $delta) => (
  $box.bump($delta)
)

macro Expression $macro_postfix_callable(Expr $box, Expr $value) => (
  $box.callable($value)
)

macro Expression $macro_postfix_keyword(Expr $value) => (
  $value.int()
)

int main(void) {
  MacroPostfixBox box = {
    .value = 41,
    .callable = add_one
  };
  MacroPostfixBox *pointer = &box;
  Var boxed = 41;
  printf(
    "%d %d %d %d %d %d\n",
    $macro_postfix_field(box),
    $macro_postfix_field(pointer),
    $macro_postfix_arrow(pointer),
    $macro_postfix_method(box, 3),
    $macro_postfix_callable(box, 41),
    $macro_postfix_keyword(boxed)
  );
  return 0;
}
