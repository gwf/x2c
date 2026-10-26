/*  list-rest.x -- separate arguments and explicit List splices
*/

#include <assert.h>
#include "type.x"

static List collect(.... items) => items;
static int count_after(int fixed, .... items) => fixed + items.len();

static int String.count_items(String label, .... items) {
  printf("%s: %d\n", label, items.len());
  return items.len();
}

int main(void) {
  List pair = %(2 3), empty = NULL;
  assert(!collect());
  assert(collect(pair) == %($pair));
  Type integer = %(int), real = %(double);
  assert(collect(integer, real) == %($integer $real));
  assert(collect(1, @pair, @empty, 4) == %(1 2 3 4));

  int (*count)(int, .... items) = count_after;
  assert(count(10, pair) == 11);
  assert(count(10, @pair) == 12);

  Func dynamic = count_after, all = collect;
  assert(dynamic(10, 1, @pair, 4) == 14);
  assert(all(pair).list() == %($pair));
  assert(all(@empty).list() == empty);

  String label = "items";
  label.count_items(1, @pair, 4);
  puts("List arguments stay nested; explicit splices expand.");
  return 0;
}
