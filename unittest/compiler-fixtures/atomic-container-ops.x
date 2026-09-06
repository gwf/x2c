#include "x2c.x"

typedef Array Scores;
typedef Map Totals;
typedef String Text;

static Scores saved_array;
static Totals saved_map;
static int base_calls;
static int selector_calls;
static int rhs_calls;

static Scores array_base(void) {
  base_calls++;
  return saved_array;
}

static Totals map_base(void) {
  base_calls++;
  return saved_map;
}

static int next_index(int value) {
  selector_calls++;
  return value;
}

static Var next_key(String value) {
  selector_calls++;
  return value;
}

static Var next_rhs(int value) {
  rhs_calls++;
  return value;
}

int main(void) {
  Scores dst_array = %[10, 20, 30, 40, 50, 60], src_array = %[2, 3];
  Totals dst_map = %{"a": 100, "b": 200}, src_map = %{"s": 4};
  saved_array = dst_array;
  saved_map = dst_map;

  Var value = array_base()[next_index(0)] += next_rhs(3);
  Var aa = array_base()[next_index(1)] +=
           src_array[next_index(0)];
  Var am = array_base()[next_index(2)] -=
           (src_map[next_key(%"s")]);
  Var ma = map_base()[next_key(%"a")] +=
           src_array[next_index(1)];
  Var mm = map_base()[next_key(%"b")] *=
           src_map[next_key(%"s")];
  Var complex = array_base()[next_index(3)] +=
                src_array[next_index(0)] * 2;
  Var casted = array_base()[next_index(4)] +=
               (Var) src_array[next_index(1)];
  Var same = array_base()[next_index(4)] +=
             dst_array[next_index(4)];
  Var prefix = ++array_base()[next_index(5)];
  Var postfix = array_base()[next_index(5)]--;

  Var counter = 7;
  Var direct_prefix = ++counter;
  Var direct_postfix = counter--;
  Var dynamic = Var.new(<string>, %"x");
  Var sum = dynamic + "y";
  dynamic += %"z";
  Text text = %"native";
  text += "!";

  int native[2] = { 1, 2 };
  native[0] += native[1];
  native[1]++;

  printf("values=%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",
         value.int(), aa.int(), am.int(), ma.int(), mm.int(),
         complex.int(), casted.int(), same.int(), prefix.int(),
         postfix.int());
  printf("direct=%d,%d,%d strings=%s,%s,%s native=%d,%d\n",
         direct_prefix.int(), direct_postfix.int(), counter.int(),
         sum.string(), dynamic.string(), text, native[0], native[1]);
  printf("calls=%d,%d,%d\n", base_calls, selector_calls, rhs_calls);
  return 0;
}
