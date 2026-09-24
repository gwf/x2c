/* style.x -- positive cases for the style rules in a src/ unit.
   This comment is deliberately written and simply robust. */
#include <stdio.h>

typedef struct Compiler { int token, depth, state_depth; } *Compiler;

int helper(int value);
int elsewhere(int value);

int helper(int value) => value + 1;

static int _call(int one, int two) => one + two;

static const char *table[][3] = {
  {"one indivisible literal", "two", "three indivisible literal that keeps it"},
};

// --------------------------------------------------------------------
// return the sum of both values
static int _add(int left, int right) => left +  right;

int Compiler.parse_expression(Compiler c, int token, int depth, int more) =>
  token + depth + more;

int Compiler.size(Compiler c) => c.depth;

int Compiler.parse(Compiler compiler, int depth) {
  return compiler.parse_expression(
    compiler.token, depth + 1, compiler.state_depth);
}

int Compiler.symmetric(Compiler left, Compiler right) =>
  left.parse_expression(right.token, left.depth, right.state_depth);

int Var.negated(Var value) => !(value is <list>);

void run(int ready, Compiler c) {
  int value;
  value = _call(1,
    2);
  value = _call(
      1, 2);
  value = _call(
    1,
    2
  );
  if (ready) {
    value = helper(value);
  }
  if (ready)
    value = helper(value);
  value = c.size() + _add(c.token, c.size()) + helper(c.size());
	value = 0;
  value = 1; 


  puts("one");
  fputs("two\n", stdout);
  value = _call(value, _add(value, value)) + _call(value, value) + _call(1, 12);
  puts("a string that makes this line longer than seventy-nine columns in all");
}
