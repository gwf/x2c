#include "x2c.x"

typedef struct DelegateCycleLeft *DelegateCycleLeft;
typedef struct DelegateCycleRight *DelegateCycleRight;

struct DelegateCycleLeft {
  delegate DelegateCycleRight right;
};

struct DelegateCycleRight {
  delegate DelegateCycleLeft left;
};

int main(void) {
  DelegateCycleLeft value = NULL;
  return value.missing();
}
