/* References borrow caller storage; call without &. Rest parameters collect
   arguments into a List or Map. @ explicitly splices arguments. */
static int square(int n) => n * n;
static void increment(int &n) => n++;
static List collect(List @items) => items;
static String describe(String name, Map @options) =>
  %"$name: $(options.getdefault(<count>, 1))";

int main(void) {
  auto {
    int count = 3;
    increment(count);
    List pair = %(2 3);
    printf("functions: %d; %s; %s\n",
           square(count), collect(1, @pair).repr(),
           describe("items", count: count));
    Func snapshot = %!() => count;
    Func update = %!(int n) using &count => count += n;
    count = 10;
    Var old = snapshot(), next = update(2);
    printf("   captured %s; shared %s; local %d\n", old, next, count);
    List doubled = pair.map(%!(int n) => n * 2);
    Var total = pair.iter().map(square).foldl(0, %!(int a, int b) => a + b);
    printf("   mapped %s; lazy squares total %s\n", doubled.repr(), total);
  }
  return 0;
}
