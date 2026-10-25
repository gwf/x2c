#include "x2c.x"

meta static int sequenced(void) {
  x2c_diagnostic_warn("sequence warning", %("sequence note"));
  return 7;
}

meta static int nil_value(void) {
  x2c_diagnostic_warn("nil warning", NULL);
  return 1;
}

meta static int final_warning(void) {
  int value = 9;
  x2c_diagnostic_warn("final warning", NULL);
  return value == 9;
}

meta static int two(void) {
  x2c_diagnostic_warn("first warning", %("first note"));
  x2c_diagnostic_warn("second warning", %("second note"));
  return 11;
}

int main(void) {
  printf("%d %d %d %d\n", $sequenced(), $nil_value(), $final_warning(),
         $two());
  return 0;
}
