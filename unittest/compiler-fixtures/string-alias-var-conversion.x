#include "x2c.x"

class Name String;
typedef String Label;

static const char *shown(String text) => text ? text : "NULL";

int main(void) {
  Var words = %(alpha beta), text = %"alpha", number = 42;
  foreach (Var value, %($words $text $number)) {
    String string = value;
    Name name = value;
    Label label = value;
    printf("%s %s %s\n", shown(string), shown(name), shown(label));
  }
  List mixed = %(symbol 2 (nested) "text");
  foreach (String string, mixed) printf(" %s", shown(string));
  printf("\n");
  foreach (Name name, mixed) printf(" %s", shown(name));
  printf("\n");
  foreach (Label label, mixed) printf(" %s", shown(label));
  printf("\n");
  return 0;
}
