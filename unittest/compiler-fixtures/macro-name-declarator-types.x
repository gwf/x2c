/* In a template, a declaration whose declarator is a `Name` hole accepts
   every type an ordinary identifier declarator accepts: a builtin type,
   `_Bool` and `bool`, a typedef name, a struct tag, a pointer, and a `Type`
   hole. The decorator declares the caller's name for the statements after
   it. */

#include "x2c.x"
#include <stdbool.h>

typedef struct Move { int card; } Move;

macro Decorator $flagged(Stmt $body, Name $flag) {
  bool $flag = false;
  {
    $body
    $flag = true;
  }
}

macro Stmt $declare_all(Name $a, Name $b, Name $c, Name $d, Name $e) {
  _Bool $a = 1;
  Move $b = { 2 };
  struct Move $c = { 3 };
  Move *$d = &$b;
  unsigned $e = 5;
}

macro Unit $typed(Type $kind) {
  macro Decorator $holding(Stmt $body, Name $held) {
    $kind $held = 9;
    { $body }
  }
}
$typed(long);

int main(void) {
  $flagged(done) puts("flagged");
  $declare_all(a, b, c, d, e);
  $holding(h) puts("holding");
  printf("%d %d %d %d %d %u %ld\n", done, a, b.card, c.card, d->card, e, h);
  return 0;
}
