#include "x2c.x"

#define NAMED_FORMAT "%s\n"

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

  // A converter call that takes further postfix syntax is a receiver, and a
  // call the macro builds is not the one source spelled.
  macro Expression as_text(Expr $value) => ($value.str())
  int width = v.str().len();
  String built = as_text(v);

  // A format the compiler cannot read at translation time converts nothing.
  const char *chosen = "%s\n";
  printf(chosen, v.str());
  printf(NAMED_FORMAT, v.str());

  // A method-form format drops its receiver from the argument list, but not
  // from the family's argument positions.
  String joined = "%s-%s".printf(v.str(), v.str());
  Buffer out = Buffer.new(0);
  out.printf("%s\n", v.str());
  printf("%d %s %s", width, built, joined);
  printf("%s", out.str());
  out.free();
  (void)boxed; (void)holes;
  return 0;
}
