#include "x2c.x"

typedef struct Widget {
  int id;
} *Widget;

protocol Measure(Widget) {
  int Widget.magnitude(Widget);
}

int main(void) {
  printf("ok\n");
  return 0;
}
