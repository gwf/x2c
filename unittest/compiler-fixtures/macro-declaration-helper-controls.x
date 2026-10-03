#include "x2c.x"
$(import "macro-declaration-helper.xmacro")

macro Stmt $sum_lengths(Name $out) {
  $declare_list(items);
  foreach (String item, items) $out += item.len();
  $let(items, %("f")) {
    foreach (String item, items) $out += item.len();
  }
}
macro Expression $invoke(Name $callee) => $callee(3);
static int increment(int value) { return value + 1; }

typedef struct Record { int value; } Record;
macro Expression $member(Expr $record, Name $name) => $record.$name;

int main(void) {
  int result = 0;
  List items = %("untouched");
  $sum_lengths(result);
  $sum_lengths(result);
  macro Stmt declare_local(Name $name) { String $name = "abc"; }
  macro Stmt measure_local(Name $out) {
    declare_local(text);
    $out += text.len();
  }
  int text = 70;
  measure_local(result);
  Record record = {.value = 8};
  int value = 9;
  printf("%d %d %d %d %d\n", result, (int) items.len(), text,
    $invoke(increment), $member(record, value));
  return result != 15 || items.len() != 1 || text != 70 ||
    $invoke(increment) != 4 || $member(record, value) != 8;
}
