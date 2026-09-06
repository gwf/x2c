#include "x2c.x"

$(import "macro-invocation-location-import.xmacro")

keyword LOCATION $fixture.location;

static int location_values(char *file, int line, int column) {
  printf("%s:%d:%d\n", file, line, column);
  return 0;
}

int main(void) {
  int direct = $fixture.location();
  int nested = $fixture.nested_location();
  int alias = LOCATION();
  return direct + nested + alias;
}
