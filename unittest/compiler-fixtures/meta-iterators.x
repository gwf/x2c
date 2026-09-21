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

meta int folds(void) {
  Array values = [1, 2, 3];
  return %(1 2 3).foldl(void, %!(Var a, Var b) => a + b).integer() * 100 +
    values.foldl(void, %!(Var a, Var b) => a + b).integer() * 10 +
    range(1, 3, 1).foldl(void, %!(Var a, Var b) => a + b).integer();
}

meta int void_consumers(void) {
  return %().foldl(void, (Func) 0).is_void() &&
    range(1, 0, 1).foldl(void, (Func) 0).is_void() &&
    range(1, 0, 1).next().is_void() &&
    range(1, 0, 1).find(%!(Var value) => value).is_void() &&
    range(1, 0, 1).min().is_void() &&
    range(1, 0, 1).max().is_void() &&
    %(4 5).foldl(void, (Func) 0).integer() == 4;
}

meta int found(void) {
  return %(0 2 3).find(%!(Var value) => value).integer() * 10 +
    range(1, 3, 1).find(%!(Var value) => value > 1).integer();
}

int main(void) {
  printf("%s\n%d %d %d %d %d\n%d %d %d\n", mapped(10).str(),
    keys_valid(), independent(), lazy(), live_map(), x2c_truth(), folds(),
    void_consumers(), found());
  return 0;
}
