#include "x2c.x"

static String _label(Var v) {
  return v.str();
}

static int _count(List items) => items.len();

static int _pair(List a, List b) => a.len() + b.len();

static void _write(const char *text) { printf("%s", text); }

typedef struct Label { int id; } *Label;

String Label.str(Label label) => "label";
String Label.string(Label label) => "text";

int main(void) {
  Var v = "one";
  String s = v.str();
  Var boxed = s.var();
  Symbol sym = <alpha>;
  String name = sym.str();
  int count = _count(v.list());
  int pair = _pair(v.list(), v.list());
  s = v.str();
  String hole = %"value ${v.str()}";
  List holes = %(${s.var()});
  int chained = v.list().len();
  _write(v.string());
  printf("%s %s %s %d %d %s\n", _label(v), name, hole, count, chained,
         v.str());
  printf("%s %s %d\n", v.str(), v.str(), pair);
  long raw = v.integer();
  Label label = NULL;
  String text = label.string();
  printf("%s %ld %s\n", v.string(), raw, text);
  (void)boxed; (void)holes;
  return 0;
}
