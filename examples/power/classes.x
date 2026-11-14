#include <assert.h>

class Color { int red, green, blue; };

int main(void) {
  // Construction follows field order; equality compares every field.
  Color coral = Color.new(255, 127, 80);
  Color same = Color.new(255, 127, 80);
  assert(coral == same);

  // Generated hashing and equality let equal colors share a Map entry.
  Map names = {(coral): "coral"};
  assert(names[same] == "coral");

  // Colors also work as Array elements.
  Array palette = [Color.new(255, 127, 80), Color.new(70, 130, 180)];
  assert(palette[0] == coral);

  // Printing includes the class name and each named field.
  printf("%s: %s\n", names[same], coral.repr());
  return 0;
}
