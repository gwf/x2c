#include "x2c.x"

int main(void) {
  match (%(tag present)) {
    case %(tag (!not ?missing)):
      return 1;
  }
  return 0;
}
