#include "x2c.x"
#include <assert.h>

typedef Array Values;
typedef Map Dict;
typedef Map TextDict;
typedef String Name;
typedef int *Numbers;

static int array_reads, map_reads;

Var Values.getindex(Values values, int index) {
  array_reads++;
  return values[index].integer() + 40;
}

Var Dict.getindex(Dict dict, Var key) {
  map_reads++;
  return dict[key].integer() + 40;
}

String TextDict.getindex(TextDict dict, Var key) {
  (void) dict;
  (void) key;
  return "override";
}

int Name.getindex(Name name, int index) => name[index] + 1;
int Numbers.getindex(Numbers numbers, int index) => ((int *) numbers)[index] + 40;

int main(void) {
  Values values = [1, 2];
  Dict dict = {};
  dict[1] = 2;
  Name name = "ab";
  int native[] = {3, 4};
  Numbers numbers = native;

  assert(values[1].integer() == 42 && array_reads == 1);
  assert(dict[1].integer() == 42 && map_reads == 1);
  assert(name[0] == 'b');
  assert(numbers[1] == 44);

  values[1] = 7;
  values[1] += 3;
  values[1]++;
  dict[1] = 7;
  dict[1] += 3;
  dict[1]++;
  Array array_base = values;
  Map map_base = dict;
  assert(array_base[1].integer() == 11 && array_reads == 1);
  assert(map_base[1].integer() == 11 && map_reads == 1);
  assert(values[1].integer() == 51 && array_reads == 2);
  assert(dict[1].integer() == 51 && map_reads == 2);

  TextDict typed = {};
  Var assigned = (typed[1] = 17);
  Var updated = (typed[1] += 3);
  Var before = typed[1]++;
  Var after = ++typed[1];
  Map typed_base = typed;
  assert(assigned.integer() == 17 && updated.integer() == 20);
  assert(before.integer() == 20 && after.integer() == 22);
  assert(typed_base[1].integer() == 22);
  assert(typed[1] == "override");
  puts("alias override and mutation passed");
  return 0;
}
