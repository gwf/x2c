#include "x2c.x"

typedef struct Before { int value; } Before;

int before_size(Before value) => value.value;

/* A typedef after a function definition is source-private unless a public
   prototype names it; the header must then be able to spell it. */
typedef struct After { int value; } After;
typedef struct Hidden { int value; } Hidden;

int after_size(After value) => value.value;

static int hidden_size(Hidden value) => value.value;

int main(void) {
  After after = { 2 };
  Hidden hidden = { 3 };
  return after_size(after) + hidden_size(hidden) == 5 ? 0 : 1;
}
