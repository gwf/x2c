#include "x2c.x"
#include "meta.x"

/* A function type written without `(*)` keeps its parameters: a `(` that
   a type or `)` follows opens a parameter list, not a nested declarator,
   and a typedef name there is a type, as in C. */
meta static String function_types(void) {
  Array types = [];
  types.push($!(int (int)){ 0 }.cadr().repr());
  types.push($!(Func (void)){ 0 }.cadr().repr());
  types.push($!(void *(String, String)){ 0 }.cadr().repr());
  types.push($!(int (*)(int)){ 0 }.cadr().repr());
  return "\n".join(types);
}

int main(void) {
  printf("%s\n", $function_types());
  return 0;
}
