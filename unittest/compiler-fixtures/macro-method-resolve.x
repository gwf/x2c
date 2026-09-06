#include "x2c.x"

$(import "macro-method-resolve-import.xmacro")

int main(void) {
  String value = "method";
  printf("%d %d %d %d %d\n",
         $string_len(value),
         $has_method(String, len),
         $has_method(Map, try_next),
         $has_method(Bytes, truth),
         $has_method(Map, missing));
  return 0;
}
