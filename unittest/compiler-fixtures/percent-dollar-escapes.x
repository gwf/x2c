#include "x2c.x"
#include <stdio.h>

int main(void) {
  String name = "name";
  String escaped = %"\$\$", doubled = %"a$$$$", mixed = %"\$$$";
  String interpolated = %"\$${name}x$$${name}\$";
  String backslash = %"\\$$", decoded = %"\x24\044";
  String ordinary = "$$";
  printf("%d:%s %d:%s %d:%s\n", escaped.len(), escaped,
         doubled.len(), doubled, mixed.len(), mixed);
  printf("%s %s %s %s\n", interpolated, backslash, decoded, ordinary);
  puts("$$");
  List data = %("a$$" "\$\$");
  printf("%s %s\n", data[0].str(), data[1].str());
  return 0;
}
