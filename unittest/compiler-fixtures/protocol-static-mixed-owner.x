#include "x2c.x"

typedef struct StaticFirst {
  int value;
} *StaticFirst;

typedef struct StaticSecond {
  int value;
} *StaticSecond;

typedef struct StaticMixed {
  int value;
} *StaticMixed;

protocol StaticFirst(T) {
  int T.read(T);
}

protocol StaticSecond(T) {
  int T.read(T);
}

StaticFirst StaticMixed.staticfirst(StaticMixed value) {
  return (StaticFirst) value;
}

StaticMixed StaticFirst.staticmixed(StaticFirst value) {
  return (StaticMixed) value;
}

StaticSecond StaticMixed.staticsecond(StaticMixed value) {
  return (StaticSecond) value;
}

StaticMixed StaticSecond.staticmixed(StaticSecond value) {
  return (StaticMixed) value;
}

int StaticFirst.read(StaticFirst value) {
  return value.value;
}

int StaticSecond.read(StaticSecond value) {
  return value.value;
}

static protocol StaticFirst(StaticMixed);
protocol StaticSecond(StaticMixed);

int main(void) {
  return 0;
}
