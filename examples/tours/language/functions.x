#include "system-macros.x"

/* References borrow caller storage; call without &. Rest parameters collect
   arguments into a List or Map. @ explicitly splices arguments. */
static int square(int n) => n * n;
static void increment(int &n) => n++;
static List collect(List @items) => items;
static String describe(String name, Map @options) =>
  %"$name: $(options.getdefault(<count>, 1))";

int main(void) {
  int count = 3;
  increment(count);
  List pair = %(2 3);
  puts($dedent(%"
    Square: $(square(count))
    Collected arguments: $(collect(1, @pair).repr())
    Item description: $(describe("items", count: count))"));
  Func snapshot = %!() => count;
  Func update = %!(int n) using &count => count += n;
  count = 10;
  Var old = snapshot(), next = update(2);
  puts($dedent(%"
    Captured value: $old
    Shared value: $next
    Local value: $count"));
  List doubled = pair.map(%!(int n) => n * 2);
  Var total = pair.iter().map(square).foldl(0, %!(int a, int b) => a + b);
  puts($dedent(%"
    Doubled items: $(doubled.repr())
    Sum of squares: $total"));
  return 0;
}
