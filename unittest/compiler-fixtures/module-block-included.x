/* A unit that includes a module's entry collects the public declarations
   of its members. */
#include "module-block-included/shapes.x"

int main(void) {
  struct Square square = { 2 };
  return square_area(square);
}
