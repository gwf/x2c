#include "x2c.x"

typedef Var Dynamic;
typedef Dynamic DynamicAlias;

int main(void) {
  Var key = 23;
  Dynamic val = 3.14;
  DynamicAlias answer = %"hello";
  Var width = 6, precision = 1, letter = 'A', whole = 7;
  char first[80], second[80], third[80];

  printf("printf:(%d:%.2lf)=%s native=%d %%\n",
         key, val, answer, 9);
  fprintf(stdout, "fprintf:%hhd/%hu\n", key, key);
  sprintf(first, "sprintf:%lld/%s", key, answer);
  snprintf(second, sizeof second, "snprintf:%#x/%*.*f",
           key, width, precision, whole);
  snprintf(third, sizeof third, "native:%zu/%p var=%d",
           sizeof third, (void *) NULL, key);

  String string =
    %"string:%hhd/%hu/%Lf/%s".printf(key, key, val, answer);
  Stdout.printf("file:%c/%u\n", letter, key);
  Buffer buffer = Buffer.new(0);
  buffer.printf("buffer:%ld/%g", key, val);

  printf("%s\n%s\n%s\n%s\n", first, second, string, buffer.str());
  buffer.free();
  return 0;
}
