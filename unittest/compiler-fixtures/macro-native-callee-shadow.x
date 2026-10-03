#include "x2c.x"
#include <time.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>

/* Each macro keeps the native function with `using`, so a caller's local of
   the same spelling does not supply it. */
macro Expression $now() using time => time(NULL) > 0;
macro Expression $size(Expr $text) using strlen => ((strlen))($text);
macro Stmt $dispose(Expr $pointer) { using free; free($pointer); }
macro Stmt $write(Expr $text) { using fputs; fputs($text, stdout); }
macro Stmt $quit() { using exit; exit(0); }
macro Expression $letter(Expr $ch) using isalpha => isalpha($ch) != 0;

static int absent(void) { return $now() && $size("abc") == 3; }

int main(void) {
  int time = 11, strlen = 12, free = 13, fputs = 14, exit = 15;
  int isalpha = 16;
  void *pointer = malloc(1);
  int present = $now() && $size("abcd") == 4 && $letter('a');
  $dispose(pointer);
  $write("native ");
  if (0) $quit();
  printf("%d %d %d\n", absent(), present,
    time + strlen + free + fputs + exit + isalpha);
  return !present || !absent();
}
