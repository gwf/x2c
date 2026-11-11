/* An `Entry @options` hole spliced into a call forwards its `key: value`
   rows as the call's entries: to a `Map @rest` function, to a `Map @rest`
   method through a method form, and to another macro's Entry hole. No rows
   forward an empty Map. */

#include "x2c.x"

typedef struct Ui { int unused; } Ui;

static String label(String text, Map @options) {
  int size = options.getdefault(<size>, 12).integer();
  return %"$text@$size/$(options.len())";
}

static String Ui.caption(Ui ui, String text, Map @options) =>
  label(text, @options);

macro Expression $label(Expr $text, Entry @options) =>
  label($text, @options);

macro Expression $Ui.caption(Expr $ui, Expr $text, Entry @options) =>
  $ui.caption($text, @options);

macro Expression $relabel(Expr $text, Entry @options) =>
  $label($text, @options);

int main(void) {
  Ui ui = {};
  printf("%s %s %s\n", $label("a"), $label("b", size: 20),
         $label("c", size: 8, weight: 2));
  printf("%s %s\n", ui.caption("d"), ui.caption("e", size: 30));
  printf("%s %s\n", $relabel("f"), $relabel("g", size: 40, weight: 1));
  return 0;
}
