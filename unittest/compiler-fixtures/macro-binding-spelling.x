#include "x2c.x"

meta static List ident_of(List value) {
  match (value) { case %(expr ? ?ident): return ident; }
  return %();
}

meta static List binding_of(List value) {
  match (value) { case %(expr ? (ident ?binding)): return binding; }
  return %();
}

meta static List bind_of(List value) => %(bind $(binding_of(value)) ());

macro Expression $expr_spelling(Expr $value) =>
  $Code.binding_spelling($value);

macro Expression $name_spelling(Name $value) =>
  $Code.binding_spelling($value);

macro Expression $ident_spelling(Expr $value) =>
  $Code.binding_spelling($ident_of($value));

macro Expression $identity_spelling(Expr $value) =>
  $Code.binding_spelling($binding_of($value));

macro Expression $bind_spelling(Expr $value) =>
  $Code.binding_spelling($bind_of($value));

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
