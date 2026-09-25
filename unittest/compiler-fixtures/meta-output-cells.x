/* Native and meta status cells and represented absence values agree. */
#include "x2c.x"

struct SymbolCell { Symbol value; };

meta int output_cells(int unused) {
  (void) unused;
  long integer = 9;
  double floating = 9.0;
  int cursor = 0, byte = 9;
  if (!"42".try_long(&integer) || integer != 42 ||
      "bad".try_long(&integer) || integer != 42 ||
      !"1.25".try_double(&floating) || floating != 1.25 ||
      "bad".try_double(&floating) || floating != 1.25 ||
      !"A".try_next(&cursor, &byte) || cursor != 1 || byte != 'A' ||
      "A".try_next(&cursor, &byte) || cursor != 1 || byte != 'A')
    return 0;

  List bindings = %(old);
  if (!%(tag value).try_match(%(tag ?item), bindings) ||
      bindings.assoc(<?item>) != <value>)
    return 0;
  List prior = bindings;
  if (%(tag value).try_match(%(other), bindings) || bindings !== prior)
    return 0;

  Var result = <old>;
  if (!%(tag value).try_match_replace(
        %(tag ?item), <?item>, result) || result != <value>)
    return 0;
  result = <old>;
  if (%(tag value).try_match_replace(%(other), <changed>, result) ||
      result != <old>)
    return 0;

  Var found = <old>;
  bindings = %(old);
  if (!%((item 7)).try_search(%(item ?value), found, bindings) ||
      found != %(item 7).var() || bindings.assoc(<?value>) != 7)
    return 0;
  found = <old>;
  bindings = %(old);
  prior = bindings;
  if (%((item 7)).try_search(%(missing), found, bindings) ||
      found != <old> || bindings !== prior)
    return 0;

  Map map = {"x": Var.null()};
  Var value = 7;
  if (!map.try_get("x", value) || !value.is_null()) return 0;
  value = 9;
  if (map.try_get("missing", value) || value != 9) return 0;
  map["remove"] = 7;
  if (!map.try_del("remove", value) || value != 7) return 0;
  value = 9;
  if (map.try_del("remove", value) || value != 9) return 0;

  Symbol symbol = <old>;
  if (!Symbol.try_new("valid", &symbol) || symbol != <valid>) return 0;
  symbol = <old>;
  if (Symbol.try_new("read_only", &symbol) || symbol != <old>) return 0;

  struct SymbolCell cell = { <old> };
  if (!Symbol.try_new("field", &cell.value) || cell.value != <field>)
    return 0;
  cell.value = <old>;
  return !Symbol.try_new("read_only", &cell.value) && cell.value == <old>;
}

meta int represented_results(int unused) {
  (void) unused;
  Array heap = [3, 1, 2];
  heap.heapify();
  if (heap.heap_pop() != 1 || heap.heap_pop() != 2 ||
      heap.heap_pop() != 3 || heap.heap_pop() is not void)
    return 0;

  Map map = {"x": Var.null()};
  Var key = "x";
  if (!map.get_hashed(key, key.hash()).is_null() ||
      map.get_hashed("missing", ((Var) "missing").hash()) is not void)
    return 0;

  Var source = (long) 7, clone = source.clone_wide(), values = %(7 8);
  return clone.compare(source) == 0 && !clone.same(source) &&
    ((Var) 7).clone_wide() is void && values.getindex(1) == 8 &&
    values.getindex(9) is void && Var.null().is_null() &&
    !Var.null().is_void() && !Var.null().is_nil();
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $output_cells(0), output_cells(argc - 1));
  printf("%d %d\n", $represented_results(0),
    represented_results(argc - 1));
  return 0;
}
