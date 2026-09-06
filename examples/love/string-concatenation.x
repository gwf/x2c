#include <stdio.h>


int main(void) {
  String lhs = %"hello, ", rhs = %"world", combined = lhs + rhs;
  printf("combined: %s\n", combined);

  String literal = "foo" + "bar";
  printf("literal: %s\n", literal);

  char *suffix = "friend";
  String mixed = lhs + suffix;
  printf("mixed: %s\n", mixed);
  return 0;
}
