#include "x2c.x"

macro Expression $raw_segment() =>
  $(quote (expr ("String") (segments (segraw "raw"))));

int main(void) {
  String value = $raw_segment();
  puts(value);
  return value == %"raw" ? 0 : 1;
}
