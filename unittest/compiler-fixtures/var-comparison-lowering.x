#include "x2c.x"

static int left_calls;
static int right_calls;

static Var mark_left(Var value) {
  left_calls++;
  return value;
}

static Var mark_right(Var value) {
  right_calls++;
  return value;
}

int main(void) {
  int native_eq = 3 == 3;
  int native_ne = 3 != 4;
  int native_same = 3 === 3;
  int native_different = 3 !== 4;
  int native_order = 2 < 3 && 3 <= 3 && 4 > 3 && 4 >= 4;

  long precise = 9007199254740993L;
  Var first = precise, equal_value = precise, adjacent = precise + 1;

  int value_eq = first == equal_value;
  int value_ne = first != adjacent;
  int identity_eq = first === equal_value;
  int identity_ne = first !== equal_value;
  int self_identity = first === first;

  int mixed_eq_left = first == precise;
  int mixed_eq_right = precise == first;
  int mixed_identity = first === precise;
  int mixed_identity_ne = precise !== first;

  int order_lt = first < adjacent;
  int order_le = first <= equal_value;
  int order_gt = adjacent > first;
  int order_ge = equal_value >= first;
  int mixed_order_left = first < precise + 1;
  int mixed_order_right = precise < adjacent;

  Var string_a = %"a", string_b = %"b";
  int string_order = string_a < string_b;

  Array array = %[1, 2], copy = array.copy();
  Var array_value = array, copy_value = copy;
  int object_equal = array_value == copy_value;
  int object_same = array_value === copy_value;
  int object_mixed_same = array_value === array;
  int object_order_le = array_value <= copy_value;
  int object_order_ge = array_value >= copy_value;

  int marked_equal = mark_left(first) == mark_right(equal_value);

  printf("native=%d,%d,%d,%d,%d\n", native_eq, native_ne, native_same,
         native_different, native_order);
  printf("wide=%d,%d,%d,%d,%d mixed=%d,%d,%d,%d\n",
         value_eq, value_ne, identity_eq, identity_ne, self_identity,
         mixed_eq_left, mixed_eq_right, mixed_identity, mixed_identity_ne);
  printf("order=%d,%d,%d,%d,%d,%d strings=%d\n",
         order_lt, order_le, order_gt, order_ge, mixed_order_left,
         mixed_order_right, string_order);
  printf("object=%d,%d,%d,%d,%d once=%d,%d,%d\n",
         object_equal, object_same, object_mixed_same, object_order_le,
         object_order_ge, marked_equal, left_calls, right_calls);
  return 0;
}
