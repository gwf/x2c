#include "x2c.x"

typedef struct StaticBase {
  int value;
} *StaticBase;

typedef struct StaticParticipant {
  int value;
} *StaticParticipant;

protocol StaticBase(T) {
  int T.read(
    T, const int *scale, int **output, int values[3], int (*callback)(int));
}

StaticBase StaticParticipant.staticbase(StaticParticipant value) {
  StaticBase result = Scope.malloc(sizeof(struct StaticBase));
  result.value = value.value;
  return result;
}

StaticParticipant StaticBase.staticparticipant(StaticBase value) {
  StaticParticipant result =
    Scope.malloc(sizeof(struct StaticParticipant));
  result.value = value.value;
  return result;
}

int StaticBase.read(
  StaticBase value, const int *scale, int **output, int values[3],
  int (*callback)(int)) {
  **output = callback(value.value * *scale + values[0]);
  return **output;
}

static protocol StaticBase(StaticParticipant);

static int identity(int value) {
  return value;
}

int main(void) {
  StaticParticipant participant =
    Scope.malloc(sizeof(struct StaticParticipant));
  participant.value = 3;
  int scale = 2, result = 0, *output = &result, values[3] = { 4, 0, 0 };
  printf(
    "%d\n",
    participant.read(&scale, &output, values, identity)
  );
  return 0;
}
