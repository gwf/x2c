#pragma indent
/* indent.x -- the indentation syntax: brace, wrapping, and statement rules
   do not apply, and token and declaration rules do. */

int helper(int value)

int helper(int value) => value + 1

static int _call(int one, int two) => one + two

int Var.negated(Var value) => !(value is <list>)

void run(int ready):
  int value
  value = _call(1,
    2)
  if ready:
    value = helper(value)
  value = _call(value, _call(value, value)) + _call(value, value) + helper(9999)
