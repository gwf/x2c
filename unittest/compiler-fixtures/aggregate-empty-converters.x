#include "x2c.x"

typedef struct Choice { int source; } Choice;
typedef struct OnlyArray { int source; } OnlyArray;

Choice Map.choice(Map value) {
  (void) value;
  Choice result = {.source = 1};
  return result;
}

Choice Array.choice(Array value) {
  (void) value;
  Choice result = {.source = 2};
  return result;
}

OnlyArray Array.onlyarray(Array value) {
  (void) value;
  OnlyArray result = {.source = 3};
  return result;
}

int main(void) {
  Choice preferred = {};
  OnlyArray fallback = {};
  Map map = {};
  Array array = {};
  Var generic = {};
  if (preferred.source != 1 || fallback.source != 3 ||
      map.len() || array.len() || generic is not <map>) return 1;
  printf("empty converter order ok\n");
  return 0;
}
