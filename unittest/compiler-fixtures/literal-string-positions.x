#include "x2c.x"

#define GREETING "hello"

static int size(String s) => s.len();

// A C string literal becomes a String wherever C gives it no meaning, also
// when it is parenthesized, chosen by `?:`, or spelled through a macro.
int main(void) {
  int x = 1;
  printf("%d %d %d\n", ("abc").len(), (x ? "abc" : "de").len(),
         (x ? ("abc") : "de").len());
  foreach (Var ch, ("ab")) printf("%s,", ch.repr());
  foreach (Var ch, x ? "cd" : "e") printf("%s,", ch.repr());
  printf("\n");
  try raise %(boom (msg ${("text")}));
  catch %(boom (msg ?m)): printf("%s\n", m.repr());
  try raise %(boom (msg ${x ? "yes" : "no"}));
  catch %(boom (msg ?m)): printf("%s\n", m.repr());
  String s = GREETING, b = "b";
  printf("%d %d %d %d\n", size(GREETING), s.len(), GREETING.len(),
         s == GREETING);
  printf("%d %d %d %d\n", b < "c", b > "a", b <= "a", "a" >= b);
  return 0;
}
