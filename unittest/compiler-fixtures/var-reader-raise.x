/* An explicit payload reader such as `.list()`, `.map()`, or `.array()`
   raises `<no-convert>` for a Var of another tag. The implicit crossing
   into a typed destination reads NULL for another tag, and an empty List
   payload reads NULL without raising. */

#include "x2c.x"

#include <stdio.h>

static void attempt(const char *label, Var value, Symbol reader) {
  try {
    switch (reader) {
      case <list>: value.list(); break;
      case <map>: value.map(); break;
      case <array>: value.array(); break;
    }
    printf("%s: no raise\n", label);
  }
  catch %(no-convert *): printf("%s: raised no-convert\n", label);
}

int main(void) {
  Var number = 42, nothing = void, empty = %();
  attempt("list of number", number, <list>);
  attempt("list of void", nothing, <list>);
  attempt("map of number", number, <map>);
  attempt("array of number", number, <array>);
  attempt("list of empty list", empty, <list>);
  List l = number;
  Map m = number;
  Array a = number;
  printf("crossings %s %s %s\n", l ? "list" : "NULL", m ? "map" : "NULL",
         a ? "array" : "NULL");
  List payload = %(1 2);
  List same = payload;
  printf("list crossing keeps %d\n", (int) same.len());
  return 0;
}
