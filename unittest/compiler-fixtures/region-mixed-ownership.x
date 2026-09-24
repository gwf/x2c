#include "x2c.x"

static Var make(int choose) {
  if (choose) return Array.new();
  return cons(1, NULL);
}

static Var pass(int choose) => make(choose);
static Var identity(Var value) => value;

Var direct_scope(int choose) {
  $scope() { return make(choose); }
  return void;
}

Var stored_scope(int choose) {
  $scope() {
    Var value = make(choose);
    return value;
  }
  return void;
}

Var returned_argument(int choose) {
  $scope() {
    Var value = make(choose);
    return identity(value);
  }
  return void;
}

Var direct_pool(int choose) {
  Pool.open();
  defer Pool.close();
  return pass(choose);
}

void same_pool(int choose) {
  Pool.open();
  defer Pool.close();
  Var value = make(choose);
  List holder = cons(value, NULL);
  (void) holder;
}

static Var keep(Var item, int choose) {
  if (choose) {
    Array result = Array.new();
    result.push(item);
    return result;
  }
  return cons(item, NULL);
}

Var retained_argument(Var item, int choose) {
  return keep(item, choose);
}
