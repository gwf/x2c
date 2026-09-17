

#include <stdio.h>

int main(int argc, char **argv) {
  Map m = {
    foo: 1,
    bar: 2,
    baz: 3
  };
  List l = %(a b c);
  Array a = ["hello", "world", 42];
  String s = "this is a string";

  printf("Map m: %s\n", m.repr());
  printf("List l: %s\n", l.repr());
  printf("Array a: %s\n", a.repr());
  printf("String s: %s\n", s.repr());
  return 0;
}
