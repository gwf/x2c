#include "x2c.x"

typedef String (*StringCallback)(Var);
typedef int (*CompareCallback)(Var, Var);
typedef Iter (*IterCallback)(Var, Iter);

typedef struct Callbacks {
  StringCallback owner;
  StringCallback free;
  CompareCallback symbol_compare;
  CompareCallback file_equal;
  IterCallback iter;
} Callbacks;

static String echo(String value) {
  return value;
}

static Callbacks callbacks[] = {{
  .owner = $x2c.callback.adapt(StringCallback, String.str),
  .free = $x2c.callback.adapt(StringCallback, echo),
  .symbol_compare =
    $x2c.callback.adapt(CompareCallback, Symbol.compare),
  .file_equal =
    $x2c.callback.adapt(CompareCallback, File.equal),
  .iter = $x2c.callback.adapt(IterCallback, Array.iter)
}};

static StringCallback duplicate =
  $x2c.callback.adapt(StringCallback, String.str);

int main(void) {
  Scope.retain();
  String text = %"typed";
  Var boxed_text = text, alpha = <alpha>, beta = <beta>, raw_null = (Var) {0};
  Array values = %[];
  values.push(42);
  Var boxed_values = values;
  struct Iter storage;
  Iter iter = callbacks[0].iter(boxed_values, &storage);
  Var item;
  int advanced = iter.try_next(&item);
  printf("%d %s %s %d %d %d\n",
         callbacks[0].owner == duplicate,
         callbacks[0].owner(boxed_text),
         callbacks[0].free(boxed_text),
         callbacks[0].symbol_compare(alpha, beta),
         callbacks[0].file_equal(raw_null, raw_null),
         advanced ? item.int() : -1);
  Scope.release();
  return 0;
}
