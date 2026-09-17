#include "x2c.x"
int main(int argc, char **argv) {
  struct { int a, b; } p = argc > 1 ? {1, 2} : {3, 4};
  return p.a;
}
