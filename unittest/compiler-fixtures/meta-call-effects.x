#include "x2c.x"

meta static int _bump(Map state) {
  state["value"] = (int) state["value"] + 1;
  return state["value"];
}

meta static int _read(Map state) => state["value"];
meta static Map _fresh(void) {
  Map state = {};
  return state;
}

meta static int ordered(int initial) {
  Map state = {"value": initial};
  int saved = _bump(state);
  return (int) state["value"] + saved;
}

meta static int repeated(int initial) {
  Map state = {"value": initial};
  int saved = _bump(state);
  int twice = saved + saved;
  return twice * 10 + (int) state["value"];
}

meta static int discarded(int initial) {
  Map state = {"value": initial};
  int saved = _bump(state);
  (void) saved;
  (void) _bump(state);
  return state["value"];
}

meta static int snapshot(int initial) {
  Map state = {"value": initial};
  int saved = _read(state);
  state["value"] = 9;
  return saved;
}

meta static int identity(int initial) {
  Map state = _fresh();
  state["value"] = initial + 7;
  return state.contains("value") ? (int) state["value"] : -1;
}

meta static int subject(int initial) {
  Map state = {"value": initial};
  switch (_bump(state)) {
    case 0: return 0;
    case 1: return 1;
    default: return 2;
  }
}

meta static List _pair(Map state) {
  int saved = _bump(state);
  return %($saved $saved);
}

meta static int destructured(int initial) {
  Map state = {"value": initial};
  Var (left, right) = _pair(state);
  return (int) left + (int) right + 10 * (int) state["value"];
}

meta static int loop(int initial) {
  Map state = {"value": initial};
  int sum = 0;
  for (int i = 0; i < 3; i++) {
    int saved = _bump(state);
    sum += saved + saved;
  }
  return sum;
}

int main(int argc, char **argv) {
  (void) argv;
  int initial = argc - 1;
  printf("ordered %d %d\n", $(ordered 0), ordered(initial));
  printf("repeated %d %d\n", $(repeated 0), repeated(initial));
  printf("discarded %d %d\n", $(discarded 0), discarded(initial));
  printf("snapshot %d %d\n", $(snapshot 0), snapshot(initial));
  printf("identity %d %d\n", $(identity 0), identity(initial));
  printf("subject %d %d\n", $(subject 0), subject(initial));
  printf("destructured %d %d\n", $(destructured 0), destructured(initial));
  printf("loop %d %d\n", $(loop 0), loop(initial));
  return 0;
}
