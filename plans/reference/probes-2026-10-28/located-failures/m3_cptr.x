#include <string.h>
#include <stdlib.h>
int main(void) {
  char *raw = strdup("hello");
  printf("eq literal: %d\n", raw == "hello");
  String s = raw;
  printf("eq as String: %d\n", s == "hello");
  Map m = {};
  m[raw] = 1;
  printf("lookup by literal: %s\n", m["hello"].repr());
  free(raw);
  return 0;
}
