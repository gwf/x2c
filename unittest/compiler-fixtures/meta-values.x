#include "x2c.x"
#include "meta.x"
#define NATIVE_SUFFIX "word"

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

meta static String literal_value(Code text) => text.value();
meta static Var character_value(Code text) => text.value();
meta static int format_known(Code text) => text.format() != NULL;
macro Expression $decoded(Expr $value) => $literal_value($value);
macro Expression $character(Expr $value) => $character_value($value);
macro Expression $known_format(Expr $value) => $format_known($value);

int main(void) {
  printf("%s\n", $counted("fig pear fig"));
  printf("%s\n", $stack(%("a" "b" "c")));
  printf("%s\n", $parsed_symbol("answer"));
  printf("%d\n", $narrowed(42.75));
  printf("%d\n", $position(%(a b c), <c>));
  String hex = "\x025i", adjacent = "\x025" "i";
  String zero = "a\0tail", unicode = "\u00A9\U0001F642";
  String continued = "line\
continued";
  printf("literal values %d %d %d %d %d\n",
         hex == $decoded("\x025i"), adjacent == $decoded("\x025" "i"),
         zero == $decoded("a\0tail"),
         unicode == $decoded("\u00A9\U0001F642"),
         continued == $decoded("line\
continued"));
  printf("format known %d %d\n", $known_format(""),
         $known_format("pre" NATIVE_SUFFIX "post"));
  printf("character values %d %d %d\n",
         '\x000061' == $character('\x000061'),
         '\141' == $character('\141'), '\0' == $character('\0'));
  return 0;
}
