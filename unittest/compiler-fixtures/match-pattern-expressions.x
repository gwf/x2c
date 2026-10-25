#include "x2c.x"

static String label(String text) => %"<$text>";
meta static String label_text(void) => "<x>";

int main(void) {
  int hits = 0;
  String name = %"x";
  List subject = %(k "<x>");
  match (subject) case %(k ${label("x")}): hits++;
  match (subject) case %(k ${label(%"$name")}): hits++;
  match (subject)
    case %(k ${$label_text()}): hits++;
  if (hits != 3) return 1;
  printf("match expressions lower before emission\n");
  return 0;
}
