#include "x2c.x"
meta static Map shared_result(void) {
  Array row = [1];
  Map result = {};
  result[<first>] = row;
  result[<second>] = row;
  return result;
}
int main(void) {
  Map result = $shared_result();
  return result.len();
}
