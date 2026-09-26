#include "x2c.x"
meta static Array cyclic_result(void) {
  Array result = [];
  result.push(result);
  return result;
}
int main(void) {
  Array result = $cyclic_result();
  return result.len();
}
