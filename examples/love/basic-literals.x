/*  basic-literals.x -- Map, List, Array, and String literals */

int main(int argc, char **argv) {
  Map m = {
    foo: 1,
    bar: 2,
    baz: 3
  };
  List l = %(a b c);
  Array a = ["hello", "world", 42];
  String s = "this is a string";

  printf("Map m: foo=%s, bar=%s, baz=%s\n", m[<foo>], m[<bar>], m[<baz>]);
  printf("List l: %s\n", l.repr());
  printf("Array a: %s\n", a.repr());
  printf("String s: %s\n", s.repr());
  return 0;
}
