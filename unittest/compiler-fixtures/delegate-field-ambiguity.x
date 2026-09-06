#include "x2c.x"

typedef struct AmbiguousDirect { int value; } AmbiguousDirect;
typedef struct AmbiguousTerminal { int value; } AmbiguousTerminal;

typedef struct AmbiguousLink {
  delegate AmbiguousTerminal terminal;
} AmbiguousLink;

typedef struct AmbiguousOwner {
  delegate AmbiguousDirect direct;
  delegate AmbiguousLink link;
} AmbiguousOwner;

static int AmbiguousDirect.read(AmbiguousDirect value) {
  return value.value;
}

static int AmbiguousTerminal.read(AmbiguousTerminal value) {
  return value.value;
}

int main(void) {
  AmbiguousOwner owner = { { 1 }, { { 2 } } };
  return owner.read();
}
