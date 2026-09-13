#include "x2c.x"

$(import "keyword-aliases-import.xmacro")

keyword imported $fixture.imported;

imported
static int answer(void) {
  return 42;
}

int main(void) {
  printf("%d\n", answer());
  return 0;
}
