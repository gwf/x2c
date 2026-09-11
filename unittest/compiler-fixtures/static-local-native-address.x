#include "x2c.x"

static struct Item { int value; } item;
static int slots[3];
#define MEMBER member
#define ELEMENT element
#define DECAY decay
int main(void) {
  static int *member = &item.value;
  static int *element = &slots[1];
  static int *decay = slots;
  printf("%d %d %d\n", MEMBER == &item.value, ELEMENT == &slots[1],
    DECAY == slots);
  return 0;
}
