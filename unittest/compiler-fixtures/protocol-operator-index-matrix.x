#include "x2c.x"
#include <stdio.h>

typedef struct Bag {
  int slot[4];
} *Bag;

static int order = 0;
static int get_calls = 0;
static int set_calls = 0;
static int update_calls = 0;
static int postfix_calls = 0;

Var Bag.var(Bag value) {
  return Var.new(<bag>, value);
}

Bag Var.bag(Var value) {
  return (Bag) value.pointer();
}

Var Bag.getindex(Bag bag, Var key) {
  get_calls++;
  return bag.slot[key.integer()];
}

Var Bag.setindex(Bag bag, Var key, Var value) {
  set_calls++;
  bag.slot[key.integer()] = value.integer();
  return value;
}

Var Bag.updateindex(Bag bag, Var key, Symbol op, Var rhs) {
  (void) op;
  update_calls++;
  int index = key.integer();
  bag.slot[index] += rhs.integer();
  return bag.slot[index];
}

Var Bag.postfixindex(Bag bag, Var key, Symbol op) {
  postfix_calls++;
  int index = key.integer(), before = bag.slot[index];
  bag.slot[index] += op == <++> ? 1 : -1;
  return before;
}

protocol Var(Bag);

static Bag pick_bag(Bag bag) {
  order = order * 10 + 1;
  return bag;
}

static Var pick_key(int key) {
  order = order * 10 + 2;
  return key;
}

static Var pick_rhs(int value) {
  order = order * 10 + 3;
  return value;
}

int main(void) {
  x2c_register_type(%"bag");
  Bag bag = Scope.malloc(sizeof(struct Bag));
  bag.slot[1] = 4;

  order = 0;
  Var get = pick_bag(bag)[pick_key(1)];
  int get_order = order;
  order = 0;
  Var set = (pick_bag(bag)[pick_key(1)] = pick_rhs(5));
  int set_order = order;
  order = 0;
  Var update = (pick_bag(bag)[pick_key(1)] += pick_rhs(2));
  int update_order = order;
  order = 0;
  Var prefix = ++pick_bag(bag)[pick_key(1)];
  int prefix_order = order;
  order = 0;
  Var postfix = pick_bag(bag)[pick_key(1)]++;
  int postfix_order = order;

  Array array = %[1, 2];
  Var array_get = array[0];
  Var array_set = (array[0] = 3);
  Var array_update = (array[0] += 4);
  Var array_prefix = ++array[0];
  Var array_postfix = array[0]++;
  Var array_cross = (array[1] += array[0]);

  Map map = %{"k": 1, "j": 2};
  Var map_get = map[%"k"];
  Var map_set = (map[%"k"] = 3);
  Var map_update = (map[%"k"] += 4);
  Var map_prefix = ++map[%"k"];
  Var map_postfix = map[%"k"]++;
  Var map_cross = (map[%"j"] += map[%"k"]);

  printf(
    "bag=%ld,%ld,%ld,%ld,%ld,%ld",
    get.integer(), set.integer(), update.integer(), prefix.integer(),
    postfix.integer(), bag.slot[1]
  );
  printf(
    " orders=%d,%d,%d,%d,%d",
    get_order, set_order, update_order, prefix_order, postfix_order
  );
  printf(
    " calls=%d,%d,%d,%d\n",
    get_calls, set_calls, update_calls, postfix_calls
  );
  printf(
    "array=%ld,%ld,%ld,%ld,%ld,%ld,%ld",
    array_get.integer(), array_set.integer(), array_update.integer(),
    array_prefix.integer(), array_postfix.integer(), array[0].integer(),
    array_cross.integer()
  );
  printf(
    " map=%ld,%ld,%ld,%ld,%ld,%ld,%ld\n",
    map_get.integer(), map_set.integer(), map_update.integer(),
    map_prefix.integer(), map_postfix.integer(), map[%"k"].integer(),
    map_cross.integer()
  );
  return 0;
}
