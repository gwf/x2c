/* Value selectors and rendering share native results for present values.
   Runtime-dependent arguments keep the native calls from folding.
   Absent selectors follow the existing meta lookup convention. */

#include "x2c.x"
meta int selectors(int offset) {
  List xs = %((1 2) 3 4);
  Var value = xs;
  return offset + xs.caar().integer() + xs.cadr().integer() + xs.caddr().integer()
    + xs.cddr().len() + value.caar().integer() + value.cadr().integer()
    + value.caddr().integer() + value.cddr().len();
}
meta int inspect(int offset) {
  Var value = 7;
  return !offset && value.kind() == <integer> && <abc>.compare(<abd>) < 0;
}
meta String rendered(String text) {
  List xs = %("a" <b>);
  Array a = ["a", <b>];
  Map m = {"a": 1};
  return xs.str() + xs.repr() + a.str() + a.repr() + m.str() + m.repr()
    + text.str() + text.repr() + <b>.repr();
}
meta int absent_selectors(int unused) {
  (void) unused;
  List empty = %();
  List short_list = %(1);
  List nested = %(());
  Var value = empty;
  return empty.caar() == void && short_list.cadr() == void
    && short_list.caddr() == void && nested.caar() == void
    && value.cadr() == void && value.cddr().len() == 0;
}
int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $(selectors 0), selectors(argc - 1));
  printf("%d %d\n", $(inspect 0), inspect(argc - 1));
  printf("%s\n%s\n", $(rendered "a"), rendered(argc == 1 ? "a" : "b"));
  printf("%d\n", $(absent_selectors 0));
  return 0;
}
