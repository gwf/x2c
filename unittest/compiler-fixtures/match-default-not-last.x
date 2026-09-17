#include "x2c.x"

int main(void) {
  match (%(value)) {
    default:
      return 0;
    case %(value):
      return 1;
  }
  return 2;
}

// A default inside a conditional still precedes the arm after the group.
int conditional(void) {
  match (%(value)) {
#ifdef VALUE
    default:
      return 3;
#endif
    case %(value):
      return 4;
  }
  return 2;
}
