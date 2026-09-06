#include "x2c.x"

macro Expression $expr_spelling(Expr $value) => (
  $(x2c.binding.spelling $value)
)

macro Expression $name_spelling(Name $value) => (
  $(x2c.binding.spelling $value)
)

macro Expression $ident_spelling(Expr $value) => (
  $(x2c.binding.spelling (car (cdr (cdr $value))))
)

macro Expression $identity_spelling(Expr $value) => (
  $(x2c.binding.spelling
    (car (cdr (car (cdr (cdr $value))))))
)

macro Expression $bind_spelling(Expr $value) => (
  $(x2c.binding.spelling
    (list 'bind
      (car (cdr (car (cdr (cdr $value)))))
      nil))
)

int main(void) {
  int value = 42;
  printf("%s %s %s %s %s\n",
         $expr_spelling(value),
         $name_spelling(label),
         $ident_spelling(value),
         $identity_spelling(value),
         $bind_spelling(value));
  return 0;
}
