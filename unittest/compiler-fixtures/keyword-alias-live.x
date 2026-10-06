#include "x2c.x"

#include "keyword-aliases-import.x"

keyword imported $fixture.imported;

imported
static int answer(void) {
  return 42;
}

int main(void) {
  printf("%d\n", answer());
  return 0;
}
