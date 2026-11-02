#include "x2c.x"

typedef short Small;
typedef const int ConstInt;
typedef int *IntPointer;
typedef void *VoidPointer;
typedef String Label;
class Number int;

static int Number.value(Number value) => value;
String Number.str(Number value) {
  (void) value;
  return "nominal";
}

static int Label.width(Label value) => value.len();

meta int narrow(int choose) {
  Small a = 1, b = 2;
  auto result = choose ? a : b;
  result = 100000;
  return result;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("narrow %d %d %d\n", $narrow(1), narrow(1), narrow(argc));
  unsigned char a = 1, b = 2;
  auto byte = argc ? a : b;
  byte = 100000;
  printf("byte %zu %d\n", sizeof(byte), byte);
  int n = 7;
  IntPointer plain = &n;
  ConstInt *constant = &n;
  volatile int *changing = &n;
  const volatile int *both = &n;
  auto p = argc ? plain : constant;
  auto q = argc ? constant : plain;
  auto r = argc ? constant : changing;
  auto s = argc ? changing : constant;
  auto t = argc ? both : constant;
  auto u = argc ? constant : both;
  auto nil_left = argc ? 0 : plain;
  auto nil_right = argc ? plain : 0;
  auto null_left = argc ? NULL : plain;
  auto null_right = argc ? plain : NULL;
  printf("pointers %d %d %d %d %d %d %d %d %d %d\n",
    *p, *q, *r, *s, *t, *u, nil_left == NULL, *nil_right,
    null_left == NULL, *null_right);
  auto void_right = argc ? plain : (void *)0;
  auto void_left = argc - 1 ? (void *)0 : plain;
  auto qualified_left = argc - 1 ? ((void *)0) : constant;
  auto qualified_right = argc ? constant : (void *)0;
  printf("void null %d %d %d %d\n",
    *void_right, *void_left, *qualified_left, *qualified_right);
  auto alias_right = argc ? plain : (VoidPointer)(2 - 2);
  auto alias_left = argc - 1 ? (VoidPointer)0 : constant;
  auto constant_right = argc ? constant : (void *)(1 - 1);
  auto constant_left = argc - 1 ? (void *)((2 + 2) - 4) : plain;
  printf("constant null %d %d %d %d\n",
    *alias_right, *alias_left, *constant_right, *constant_left);
  Number first = Number.new(1), second = Number.new(2);
  auto number = argc ? first : second;
  String converted = argc ? first : second;
  printf("nominal %d %s\n", number.value(), converted);
  Symbol symbol = <ok>;
  auto chosen = argc ? symbol : symbol;
  printf("symbol %s\n", chosen.str());
  String text = "chosen";
  Label label = "label";
  auto text_left = argc ? text : "other";
  auto label_left = argc ? label : "other";
  printf("handles %d %d %d\n", text_left.len(),
    (argc ? text : "").split("/").len(), label_left.width());
  String empty = NULL;
  printf("empty [%s] [%s]\n", empty ? empty : "", argc ? "" : empty);
  return 0;
}
