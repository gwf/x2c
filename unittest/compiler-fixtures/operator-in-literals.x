/* An interpolated String literal is an operand on either side of `in`, as
   are `%{...}` before it and `%<<...>>` after it; the closing quote ends
   an operand for `<` as well. A block is not an operand, so the statement
   after one can still call a function named `in`. */
static int calls;

static void in(int count) { calls += count; }

int main(void) {
  String dir = "src", name = "main";
  Map units = {"src/main.x": 1};
  printf("%d %d\n", %"$dir/$name.x" in units, %"$dir/$name.h" in units);
  printf("%d %d\n", "ai" in %"$dir/$name", "x" in %"$dir/$name");
  printf("%d %d\n", <b> in %<<a b>>, <c> in %<<a b>>);
  Array maps = [%{a: 1}];
  printf("%d %d\n", %{a: 1} in maps, %{a: 2} in maps);
  printf("%d %d\n", %"$dir" < name, %"$name" < dir);
  if (calls == 0) {
    calls = 1;
  }
  in(2);
  printf("%d\n", calls);
  return 0;
}
