#include "regex.x"
#include <assert.h>

typedef List Row;
typedef Row NestedRow;
typedef List Parent;
int Parent.getindex(Parent parent, int index) {
  (void) parent;
  return 40 + index;
}
typedef Parent Child;
typedef String Name;
typedef Name NestedName;
typedef int *Numbers;

int main(void) {
  Row row = %(11 22);
  NestedRow nested = row;
  Child child = (Child) row;
  Name name = "x2c";
  NestedName nested_name = name;
  int values[] = {3, 4};
  Numbers numbers = values;
  assert(row[0].integer() == 11);
  assert(nested[-1].integer() == 22);
  Var bracket = child[0], dotted = child.getindex(0);
  assert(bracket == dotted);
  assert(name[0] == 'x');
  assert(nested_name[-1] == 'c');
  assert(numbers[1] == 4);

  $scope() {
    Regex regex = Regex.compile("(hi)");
    RegexMatch found = regex.match("hi");
    RegexCapture capture = found.capture(1);
    assert(capture[0].integer() == 1);
    assert(capture[3].string() == "hi");
    assert(found[1] == "hi");
  }
  puts("inherited indexes passed");
  return 0;
}
