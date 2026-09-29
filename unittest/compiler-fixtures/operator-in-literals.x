/* Every literal is an operand on either side of `in`. Beside a bare `[`,
   `{`, `}`, or `>>`, the keyword pass leaves `in` a name, and the parser
   reads it as the operator after a complete operand: after a C string
   literal, which joins other unknown names as preprocessor words, and
   after a parenthesized macro hole. The closing quote of an interpolated
   literal ends an operand for `<` too. */
macro Expression $listed($key) => ($key) in [1, 2];
macro Expression $listed_expr(Expr $key) => ($key) in [1, 2];

int main(void) {
  String dir = "src", name = "main";
  Map units = {"src/main.x": 1};
  printf("%d %d\n", %"$dir/$name.x" in units, %"$dir/$name.h" in units);
  printf("%d %d\n", "ai" in %"$dir/$name", "x" in %"$dir/$name");
  printf("%d %d\n", <b> in %<<a b>>, <c> in %<<a b>>);
  Array maps = [%{a: 1}], sets = [%<<a b>>];
  printf("%d %d\n", %{a: 1} in maps, %{a: 2} in maps);
  printf("%d %d %d %d\n", 2 in [1, 2], <b> in {a: 1}, {a: 1} in maps,
         %<<a b>> in sets);
  printf("%d %d %d\n", "ab" in ["ab"], $listed(2), $listed_expr(3));
  printf("%d %d\n", %"$dir" < name, %"$name" < dir);
  return 0;
}
