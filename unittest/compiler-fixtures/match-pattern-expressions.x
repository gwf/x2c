#include "x2c.x"

static String label(String text) => %"<$text>";

int main(void) {
  int hits = 0;
  String name = %"x";
  List subject = %(k "<x>");
  match (subject) case %(k ${label("x")}): hits++;
  match (subject) case %(k ${label(%"$name")}): hits++;
  match (subject)
    case %(k ${$(x2c.literal.string "<x>")}): hits++;
  if (hits != 3) return 1;
  printf("match expressions lower before emission\n");
  return 0;
}
