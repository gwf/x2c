#include "x2c.x"

typedef List converter_inherit_Base;
typedef converter_inherit_Base converter_inherit_Leaf;
typedef converter_inherit_Leaf converter_inherit_Override;
typedef int converter_inherit_Count;

converter_inherit_Count converter_inherit_Base.converter_inherit_count(
  converter_inherit_Base values) {
  return values.len();
}

String converter_inherit_Override.str(converter_inherit_Override values) {
  return values ? "override" : "empty";
}

int main(void) {
  converter_inherit_Leaf values = %(one two);
  converter_inherit_Override overridden = %(three four);
  String assigned = values;
  String interpolated = %"$values";
  converter_inherit_Count count = values;
  String exact = overridden;
  printf("%s | %s | %d | %s\n",
         assigned, interpolated, count, exact);
  return 0;
}
