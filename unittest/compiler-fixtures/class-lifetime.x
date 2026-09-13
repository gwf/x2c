#include <assert.h>

static int frees, inits, fail_init;
class Item struct { Array values; } *;
Item Item.new(int value) {
  if (value < 0) raise %(make-fail);
  Item item = Scope.calloc(1, sizeof(*item));
  item.values = %[$value];
  return item;
}
void Item.free(Item item) {
  frees++;
  item.values.free();
  Scope.free(item);
}
class Initialized struct { Array values; } *;
void Initialized.init(Initialized item) {
  inits++;
  assert((void *) item.values == NULL);
  if (fail_init) raise %(init-fail);
  item.values = %[];
}

/* Both failing constructors run twice: the first round publishes each catch
   site's process-lifetime plans and the second measures the balance. */
static int _failing_constructors(void) {
  int caught = 0;
  try {
    Item item = $auto(Item.new(-1));
  }
  catch %(make-fail): caught++;
  $scope() {
    Initialized failed = NULL;
    try failed = Initialized.new();
    catch %(init-fail): caught++;
    assert((void *) failed == NULL);
  }
  return caught;
}

int main(void) {
  size_t before = Scope.stats().live_allocations;
  $scope() {
    Item item = Item.new(1);
    assert(item.values[0].int() == 1);
  }
  assert(frees == 0);
  assert(Scope.stats().live_allocations == before);
  $scope() {
    Item item = $auto(Item.new(2));
    assert(item.values[0].int() == 2);
  }
  assert(frees == 1);
  assert(Scope.stats().live_allocations == before);

  $scope() {
    Initialized good = Initialized.new();
    assert(inits == 1);
    assert(good.values.len() == 0);
  }
  fail_init = 1;
  int caught = _failing_constructors();
  before = Scope.stats().live_allocations;
  caught += _failing_constructors();
  assert(frees == 1);
  assert(inits == 3);
  assert(caught == 4);
  assert(Scope.stats().live_allocations == before);
  puts("class lifetimes passed");
  return 0;
}
