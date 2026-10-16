#include "x2c.x"

protocol Shape(T) {
  associated Unit = long;

  int T_area(T *self);
  int T_scale(T self, int k);
  T *T_larger(T *self, T *other);
  Unit *T_width(T *self);
}

typedef struct Box { int w, h; } Box;

int Box_area(Box *self) { return self->w * self->h; }
int Box_scale(Box self, int k) { return self.w * k; }
Box *Box_larger(Box *self, Box *other) {
  return Box_area(self) >= Box_area(other) ? self : other;
}
int *Box_width(Box *self) { return &self->w; }

protocol Shape(Box);

int main(void) {
  Box b = {2, 3}, c = {4, 1};
  Box *p = &b;
  printf("%d %d %d %d\n", p.area(), b.scale(4), p.larger(&c)->w, *p.width());
  return 0;
}
