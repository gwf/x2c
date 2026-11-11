#include "x2c.x"

static int count(List @items) => items.len();
static int keys(Map @options) => options.len();

macro Expression $runtime_list(Expr $items) => count(@($items));
macro Expression $runtime_map(Expr $options) => keys(@($options));
macro Expression $sequence(Expr @items) => count(@items);

meta List _arguments(void) => $($!(1), $!(2));
macro Expression $meta_slot() => count(@_arguments());

int main(void) {
  List items = %(1 2 3);
  Map options = {first: 1, second: 2};
  printf("%d %d %d %d\n", $runtime_list(items), $runtime_map(options),
         $sequence(1, 2, 3, 4), $meta_slot());
  return 0;
}
