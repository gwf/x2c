#include "x2c.x"

meta List mapped(int bias) {
  return range(1, 4, 1).map(%!(Var value) => value + bias);
}

meta int keys_valid(void) {
  Map values = {"three": 3, "one": 1, "two": 2};
  List keys = values.keys();
  return keys.len() == 3 && keys.contains("one") &&
    keys.contains("two") && keys.contains("three");
}

meta int independent(void) {
  Map values = {"one": 1, "two": 2};
  return values.keys().count() * 10 + values.keys().count();
}

meta Var counted(Map state, Var value) {
  state["calls"] = state["calls"].integer() + 1;
  return value;
}

meta int lazy(void) {
  Map state = {"calls": 0};
  int count = range(1, 4, 1)
    .map(%!(Var value) => counted(state, value))
    .head(0).count();
  return count * 10 + state["calls"].integer();
}

meta int x2c_truth(void) {
  return range(1, 3, 1).filter(%!(Var value) => 0).count();
}

meta Var mutate_after_first(Map values, Map state, Var value) {
  if (!state["seen"].integer()) {
    values["a"] = 9;
    values["b"] = 9;
  }
  state["seen"] = state["seen"].integer() + 1;
  return value;
}

meta int live_map(void) {
  Map values = {"a": 1, "b": 2}, state = {"seen": 0};
  List seen = values.iter()
    .map(%!(Var value) => mutate_after_first(values, state, value));
  return seen.contains(9);
}

int main(void) {
  printf("%s\n%d %d %d %d %d\n", mapped(10).str(), keys_valid(),
    independent(), lazy(), live_map(), x2c_truth());
  return 0;
}
