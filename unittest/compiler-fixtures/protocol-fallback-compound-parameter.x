#include "x2c.x"

typedef struct Meters { int value; } Meters;
typedef struct Box { int w, h; } Box;

protocol Meters(T) {
  int T_area(T *self);
}

int Meters_area(Meters *self) { return self->value; }
Meters Box.meters(Box box) => (Meters) {box.w * box.h};

protocol Meters(Box);

int main(void) { return 0; }
