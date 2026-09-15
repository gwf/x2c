#include "x2c.x"

/* After the condition of `if`, `while`, `for`, or `switch` a statement
   starts, so `%(` opens a List; after any other `)` it is modulo. */

int main(int argc, char **argv) {
  int n = 7;
  List words = NULL;
  if (argc) words = %(one two);
  if (argc > 0) %(ignored).len();
  while (n > 6) n = (n) % (5);
  for (int i = 0; i < 1; i++) printf("%s\n", %(x y).repr());
  switch (argc) case 1: printf("%s %d\n", words.repr(), (n + 1) % (2));
  return 0;
}
