#include "x2c.x"

#include <stdio.h>

typedef List Chain;
typedef Chain Link;

Self Chain.rest(Self chain);

static macro Unit $chain_methods(Name $rest, Name $same, Name $count) {
  /** The chain after its first item. */
  Self Chain.$rest(Self chain) { return chain.cdr(); }
  /** The chain itself. */
  inline Self Chain.$same(Self chain) => chain;
  /** The number of items. */
  int Chain.$count(Chain chain) { return chain.len(); }
}
$chain_methods(rest, same, count);

int main(void) {
  Link link = (Link) $(1, 2, 3);
  Link rest = link.rest().same();
  printf("%d %d\n", rest.count(), Chain_rest(link).len());
  return 0;
}
