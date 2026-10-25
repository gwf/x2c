#include "x2c.x"

meta static List raw_segment_syntax(void) =>
  %(expr ("String") (segments (segraw "raw")));
macro Expression $raw_segment() => $raw_segment_syntax();

int main(void) {
  String value = $raw_segment();
  puts(value);
  return value == %"raw" ? 0 : 1;
}
