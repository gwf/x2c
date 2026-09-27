#include "x2c.x"

/* Only the String_new conversion folds; another String call is rejected. */
String change(String s) => "changed";
meta static String identity(String s) => s;

int main(void) {
  printf("%s\n", $identity(change("original")));
  return 0;
}
