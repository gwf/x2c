#include "x2c.x"

/* Meta functions build a Map, a List, an Array and a String during
   translation, and the results reach the program as literals. */

meta static List tally(List words) {
  Map counts = {};
  foreach (Var word, words) counts[word] = counts.getdefault(word, 0) + 1;
  return counts.list().sort();
}

meta static String render(List pairs) {
  Array parts = [];
  foreach (List pair, pairs)
    parts.push(pair.car().str().upper() + "=" + pair[1].str());
  return parts.join(", ");
}

meta static String counted(String text) => render(tally(text.split(" ")));

meta static String stack(List values) {
  Array items = [];
  foreach (Var value, values) items.push(value);
  items.remove(0);
  return items.join("|");
}

meta static String parsed_symbol(String text) =>
  Var.parse(text, <symbol>).symbol();

meta static int narrowed(double value) => Var.convert(value, <i32>).int();

meta static int position(List values, Symbol key) => values.index(key);

int main(void) {
  printf("%s\n", $counted("fig pear fig"));
  printf("%s\n", $stack(%("a" "b" "c")));
  printf("%s\n", $parsed_symbol("answer"));
  printf("%d\n", $narrowed(42.75));
  printf("%d\n", $position(%(a b c), <c>));
  return 0;
}
