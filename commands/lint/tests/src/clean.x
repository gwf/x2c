/* clean.x -- negative cases: source every rule accepts. */
#include <stdio.h>

typedef struct Compiler { int token, depth, state_depth; } *Compiler;

static const char *table[][3] = {
  {"one indivisible literal", "two", "three indivisible literal row value"},
};

// int fake(int value);
static String text = %"int fake(int value);";

static int _call(int one, int two) => one + two;

static List _first(List items) => items;

int Compiler.parse_expression(Compiler c, int token, int depth, int more) =>
  token + depth + more;

/* A rename that saves no line, and a subject already short. */
int Compiler.parse(Compiler compiler, int depth) {
  return compiler.parse_expression(compiler.token, depth, 0);
}

int Compiler.short(Compiler cc, int c) => cc.token + c;

/* A symmetric operation has no subject. */
int Compiler.symmetric(Compiler left, Compiler right) =>
  left.parse_expression(
    right.token + right.token + right.token, left.depth, right.state_depth);

List Var.strings(List items) => items.filter(%!(item) => item is <string>);

Symbol Var.opening(void) => <(>;

void run(int ready, int outer, int inner) {
  List form = _first(
    %(one
      two)
  );
  int value = _call(
    ready + outer + inner + ready + outer + inner + ready + outer + inner,
    "two"[0]);
  value = _call(
    value, 2) >= ready + outer + inner + ready + outer + inner + value + 99;
  if (ready) {
    int local = value;
  }
  if (outer) {
    if (inner) value = 1;
  }
  else value = 2;
  List quoted = %(bad-arg (owner ${
    %(x2c-literal (spelling value))
  }));
  if (ready) value = 3;
}
