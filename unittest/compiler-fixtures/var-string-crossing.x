/* A String destination reads a Var's String payload, the display text of
   any other value, or NULL for void and for Null. The explicit `.string()`
   extraction raises for a value that is not a String. */

#include "x2c.x"

#include <stdio.h>

static void show(const char *label, String text) {
  printf("%s=%s\n", label, text ? text : "NULL");
}

int main(void) {
  Var text = "hello", number = 42, list = %(1 2), nothing = void;
  Map map = {"k": 1};
  Var boxed = map;
  String s = text;
  show("string", s);
  String n = number;
  show("number", n);
  String l = list;
  show("list", l);
  String v = nothing;
  show("void", v);
  String m = map["absent"];
  show("absent", m);
  Var null_value = Var.null();
  String z = null_value;
  show("null", z);
  show("map", boxed);
  String exact = text.string();
  show("exact", exact);
  try {
    String wrong = number.string();
    show("wrong", wrong);
  }
  catch %(no-convert *): puts("string() of a number raised no-convert");
  printf("tag tests %d %d\n", number is <string>, text is <string>);
  return 0;
}
