#include "x2c.x"

typedef struct Plain {
  int value;
} Plain;

int main(void) {
  Plain a = { 1 }, b = { 2 };
  Plain c = a @ b;
  return c.value;
}
