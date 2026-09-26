#include "x2c.x"

$(import "meta-func-errors-native.xmacro")

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
