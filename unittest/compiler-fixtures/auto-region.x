#include "x2c.x"
#include <assert.h>
static int released;
static void drop(void *value) { released += *(int *) value; }
static void acquire(int value) {
  int *p = Scope.malloc_finalized(sizeof(int), drop);
  *p = value;
}
auto static int work(void) { acquire(4); return 7; }
auto static int arrow(void) => (acquire(8), 9);
static Scope destination;
auto (&destination) static void kept(void) { acquire(16); }
macro Stmt $region(Stmt $body) { auto { $body } }
macro Unit $regional_function(Name $name) {
  auto int $name(int value) { acquire(value); return value + 4; }
}
$regional_function(constructed);
macro Stmt $managed_record(Stmt $body) {
  auto struct { int value; } record = {1};
  $body
}
int main(void) {
  auto { acquire(1); auto { acquire(2); } assert(released == 2); }
  assert(released == 3);
  assert(work() == 7 && released == 7);
  assert(arrow() == 9 && released == 15);
  Scope *previous = Scope.top();
  int evaluations = 0;
  auto ((evaluations++, &destination)) acquire(32);
  kept();
  assert(evaluations == 1 && Scope.top() == previous && released == 15);
  destination.cleanup(); destination = NULL;
  assert(released == 63);
  auto for (int i = 0; i < 4; i++) {
    acquire(1); if (i == 0) continue; break;
  }
  assert(released == 65);
  for (int i = 0; i < 2; i++) auto { acquire(1); continue; }
  assert(released == 67);
  try { auto { acquire(1); raise %(invariant); } }
  catch %(invariant): {}
  assert(released == 68);
  try { auto (&destination) { acquire(1); raise %(invariant); } }
  catch %(invariant): {}
  assert(Scope.top() == previous && released == 68);
  destination.cleanup(); destination = NULL;
  $region({ acquire(1); });
  assert(released == 70);
  assert(constructed(1) == 5 && released == 71);
  $managed_record({ assert(released == 71); });
  auto foreach (int value in %(1 2)) { (void) value; acquire(1); }
  assert(released == 73);
  auto Array values = [];
  Array acquired = auto [];
  auto inferred = Buffer.new(0);
  values.push(1); acquired.push(2); inferred.write("ok");
  puts("auto regions ok");
  return 0;
}
