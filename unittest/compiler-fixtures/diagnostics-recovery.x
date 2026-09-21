#include "x2c.x"

/* A rejected top-level declaration is skipped whole, so reporting resumes at
   the next declaration and never inside the rejected body. */
macro Expression $embed.empty_path() =>
  $(x2c.literal.string (x2c.embed.text ""));

macro Expression $call(Expr $arguments..., Expr $final) => $final;

int parse_error(void) {
  int sum = 42 +;
  return sum;
}

int type_error(int value) {
  return value is int;
}

String path = $embed.empty_path();

int first_error_only(int value) {
  int first = value is int;
  int second = 1 +;
  return first + second;
}

int same_line(void) { return 1 +; } int next_on_line(void) { return 2 +; }

int main(void) {
  return 0;
}
