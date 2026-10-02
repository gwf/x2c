#include "x2c.x"
#include <time.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>

macro Expression $now() => time(NULL) > 0;
macro Expression $size(Expr $text) => ((strlen))($text);
macro Statement $dispose(Expr $pointer) { free($pointer); }
macro Statement $write(Expr $text) { fputs($text, stdout); }
macro Statement $quit() { exit(0); }
macro Expression $letter(Expr $ch) => isalpha($ch) != 0;

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
