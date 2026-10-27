#include "x2c.x"

/* A C string passed through a Func boxes as a String, as it does for any Var
   destination, so String, native pointer, and Var parameters accept it. */

static String echo(String s) => s;
static void show(const char *s) { puts(s); }
static Symbol tag(Var v) => v.tag();

meta static String meta_echo(void) {
  Func f = echo;
  return f("meta");
}

int main(void) {
  Func e = echo, p = show, t = tag;
  char buffer[] = "array";
  const char *text = "pointer";
  puts(e("literal").str());
  p("native"), p(buffer), p(text);
  printf("%s\n", t(text).symbol().str().str());
  printf("%s %s\n", meta_echo().str(), $meta_echo().str());
  return 0;
}
