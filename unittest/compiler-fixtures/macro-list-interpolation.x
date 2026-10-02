#include "x2c.x"
#include "meta.x"

static int order;

static int note(int value) {
  order = order * 10 + value;
  return value;
}

meta static List make_list(List value) {
  return %(expr ("List")
    (cons (expr ("String") (segments (segexp $value))) (nil)));
}

meta static Macro anonymous_list(void) =>
  macro Expression(Expr $value) => %("path: ${$value}");
meta static List apply_anonymous(List value) {
  Macro template = anonymous_list();
  return template(value);
}

macro Statement $show(Expr $value) {
  List notes = %("path: ${$value}");
  printf("%s\n", (char *) notes.repr());
}

macro Expression $notes(Expr $value) => %("path: ${$value}");
macro Expression $nested(Expr $value) => %(("path: ${$value}"));
macro Expression $percent(Expr $value) => %(%"path: ${$value}");
macro Expression $wrapped(Expr $value) => %(${%"path: ${$value}"});
macro Expression $text(Expr $value) => %"path: ${$value}";
macro Expression $constant() => %(fixed ("path: constant"));
macro Expression $fresh() => %([0] ({key: 0}));
macro Expression $ordered(Expr $a, Expr $b, Expr $c) =>
  %("a ${$a}" ("b ${$b}") "c ${$c}");

macro Expression $constructed(Expr $value) => $make_list($value);
macro Expression $anonymous(Expr $value) => $apply_anonymous($value);
macro Expression $lisp(Expr $value) =>
  $(list 'expr '("List")
    (list 'cons
      (list 'expr '("String") (list 'segments (list 'segexp $value)))
      '(nil)));

int main(void) {
  $show("one");
  $show("two");
  List first = $notes("one"), second = $notes("two");
  if (first[0].string() != %"path: one" ||
      second[0].string() != %"path: two") return 1;
  if ($nested("three")[0].list()[0].string() != %"path: three" ||
      $nested("four")[0].list()[0].string() != %"path: four") return 2;
  if ($percent("five") != %(% "path: five") ||
      $percent("six") != %(% "path: six")) return 3;
  if ($wrapped("seven")[0].string() != %"path: seven" ||
      $text("eight") != %"path: eight") return 4;
  String name = %"nine";
  List ordinary = %("path: $name");
  if (ordinary[0].string() != %"path: nine") return 5;
  List stable_a = $constant(), stable_b = $constant();
  if ((void *) stable_a != (void *) stable_b) return 6;
  List fresh_a = $fresh(), fresh_b = $fresh();
  fresh_a[0].array()[0] = 1;
  fresh_a[1].list()[0].map()[<key>] = 1;
  if (fresh_b[0].array()[0].integer() != 0 ||
      fresh_b[1].list()[0].map()[<key>].integer() != 0) return 7;
  List ordered = $ordered(note(1), note(2), note(3));
  if (order != 123 || ordered != %("a 1" ("b 2") "c 3")) return 8;
  List built = $constructed(note(4));
  if (order != 1234 || built != %("4")) return 9;
  if ($anonymous("ten") != %("path: ten")) return 10;
  List lisp = $lisp(note(5));
  if (order != 12345 || lisp != %("5")) return 11;
  printf("macro List interpolation ok\n");
  return 0;
}
