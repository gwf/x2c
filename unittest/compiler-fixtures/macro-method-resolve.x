#include "x2c.x"

#include "macro-method-resolve-import.x"

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
