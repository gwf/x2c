#include "x2c.x"
#include "meta.x"

/* A conditional whose arms are a `Var` and `NULL` is a `Var`: the `NULL`
   arm boxes, nested in another conditional and in a `meta` function as in
   ordinary code. */

static Type marker(void) => %(icon);

meta static Type meta_marker(void) => %(icon);
meta static int wanted(String name) => name == "icon";

meta List choose(String name, List field, List value) {
  Type type = wanted(name) ? meta_marker() : field ? field[1] : NULL;
  return type ? value : value;
}

macro Expression $pick(Expr $value) =>
  $choose("other", %("icon" ("int")), $value);

int main(void) {
  List field = %("icon" ("int"));
  int k = 0;
  Var nested = k ? marker() : field ? field[1] : NULL;
  Var grouped = k ? marker() : (field ? field[1] : NULL);
  Var empty = NULL ? NULL : NULL;
  List none = NULL;
  Var missing = none ? none[1] : NULL;
  printf("%d %d %d %d\n", nested != NULL, grouped != NULL, empty == NULL,
         missing == NULL);
  printf("%d\n", $pick(7));
  return 0;
}
