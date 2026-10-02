// Both forward callers match shipped text; the last definition is edited.
#include "x2c.x"

meta static List _tag_names(void) {
  Array names = [];
  foreach (List row, _tag_rows()) names.push(row[0]);
  return names;
}

meta static List _tag_rows(void) {
  Array rows = [];
  foreach (List group, _tag_groups())
    foreach (Var row, group) rows.push(row);
  return rows;
}

meta static List _tag_groups(void) => %(((edited)));

int main(void) {
  printf("%s %s\n", $_tag_names().repr(), _tag_names().repr());
  return 0;
}
