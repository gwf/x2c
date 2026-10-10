#include "x2c.x"
#include "rewrite.x"

static int initialized = 0;
static int next_value(void) => ++initialized;

macro Stmt $custom_try(Stmt $body, Stmt $finalizer) {
  try $body finally $finalizer
}

$rewrite($custom_try)
meta Code replace_try(Code node) {
  return $!{ {
    defer printf("cleanup\n");
    static int count = next_value();
    printf("replacement %d\n", count);
  } };
}

static void run(void) {
  try printf("body\n");
  finally printf("finally\n");
}

int main(void) {
  run();
  run();
  return initialized != 1;
}
