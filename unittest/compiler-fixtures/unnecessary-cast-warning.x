#include "x2c.x"

typedef List Ast;

int main(void) {
  String s = "hi";
  String same = (String)s;
  int n = (int)3;
  const char *text = "x";
  char *dropped = (char *)text;
  List items = [];
  Ast alias = (Ast)items;
  char buf[8], *lo = buf, *hi = buf + 3;
  int width = (int)(hi - lo);
  // The cast keeps the literal native; without it the operand would become a
  // String and the operator would be String.add.
  const char *tail = (char *)"hi" + 1;
  (void)same; (void)n; (void)dropped; (void)alias; (void)width;
  printf("%s\n", tail);
  return 0;
}
