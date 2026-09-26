#include "x2c.x"

meta int invalid_lvalue(int n) {
  Func f = %!(int &a) => a;
  return f(n + 1);
}
meta int null_reference(int n) {
  int *p = (int *) 0;
  Func f = %!(int &a) => a;
  return f(*p) + n;
}
meta int discard_qualifier(int n) {
  const int value = n;
  Func f = %!(int &a) => a;
  return f(value);
}
meta int change_pointee(int n) {
  int *p = &n;
  Func f = %!(const int *&a) => *a;
  return f(p);
}
meta int wrong_reference_type(int n) {
  unsigned value = n;
  Func f = %!(int &a) => a;
  return f(value);
}
meta int wrong_value_type(int n) {
  Func f = %!(Array a) => a.len();
  return f(n);
}
meta int concrete_void(int n) {
  Func f = %!(int a) => a;
  return f(void) + n;
}
meta int wrong_arity(int n) {
  Func f = %!(int a) => a;
  return f(n, n);
}
meta int empty_arity(int n) {
  Func f = %!(int a) => a;
  return f() + n;
}



int main(int argc, char **argv) {
  (void) argv;
  try (void) invalid_lvalue(argc);
  catch %(bad-types *): printf("invalid_lvalue bad-types\n");
  try (void) null_reference(argc);
  catch %(bad-types *): printf("null_reference bad-types\n");
  try (void) discard_qualifier(argc);
  catch %(bad-types *): printf("discard_qualifier bad-types\n");
  try (void) change_pointee(argc);
  catch %(bad-types *): printf("change_pointee bad-types\n");
  try (void) wrong_reference_type(argc);
  catch %(bad-types *): printf("wrong_reference_type bad-types\n");
  try (void) wrong_value_type(argc);
  catch %(bad-types *): printf("wrong_value_type bad-types\n");
  try (void) concrete_void(argc);
  catch %(void-op *): printf("concrete_void void-op\n");
  try (void) wrong_arity(argc);
  catch %(bad-arity *): printf("wrong_arity bad-arity\n");
  try (void) empty_arity(argc);
  catch %(bad-arity *): printf("empty_arity bad-arity\n");
  return 0;
}
