#include "x2c.x"

int main(void) {
  List input = %(node value);
  match (input) {
    case %(node ?binder?):
      return 1;
  }
  return 0;
}
