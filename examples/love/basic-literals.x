

#include <stdio.h>

int main(int argc, char **argv) {
  Map m = %{
    foo: 1,
    bar: 2,
    baz: 3
  };
  List l = %(a b c);
  Array a = %["hello", "world", 42];
  String s = %"this is a string";

  printf("Map m: %s\n", Map.repr(m));
  printf("List l: %s\n", List.repr(l));
  printf("Array a: %s\n", Array.repr(a));
  printf("String s: %s\n", String.repr(s));
  return 0;
}
