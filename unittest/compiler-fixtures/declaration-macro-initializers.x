#include "x2c.x"

// A Declaration macro keeps the initializers of the declarations it makes.

int base = 40;

int seed(void) { return 40; }

macro Expression $twice(Expr $x) => $x * 2;

macro Declaration $constant(Name $n) { int $n = 1; }
macro Declaration $computed(Name $n) { int $n = seed() + 2; }
macro Declaration $global(Name $n) { int $n = base + 3; }
macro Declaration $hidden(Name $n) { static int $n = 4; }
macro Declaration $text(Name $n) { String $n = "five"; }
macro Declaration $pair(Name $a, Name $b) { int $a = 6, $b = $a + 1; }
macro Declaration $table(Name $n) { int $n[] = {7, 8, 9}; }
macro Declaration $nested(Name $n, Expr $x) { int $n = $twice($x); }
macro Declaration $lisp(Name $n, Expr $x) { int $n = $(car (list $x)); }

$constant(one);
$computed(forty_two);
$global(forty_three);
$hidden(four);
$text(five);
$pair(six, seven);
$table(digits);
$nested(ten, 5);
$lisp(eleven, 11);

int main(void) {
  printf("%d %d %d %d %s\n", one, forty_two, forty_three, four, five);
  printf("%d %d %zu %d %d %d\n", six, seven,
         sizeof(digits) / sizeof(*digits), digits[2], ten, eleven);
  return 0;
}
