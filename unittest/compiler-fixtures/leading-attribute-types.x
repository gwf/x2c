#include "x2c.x"
#include <stdlib.h>

// Leading specifier text is written with a declaration but is no part of the
// type its names, return values, and prototypes are checked against.
macro Statement $scoped(Decl $declaration, Block $body) => {
  {
    $declaration;
    $body
  }
}

__attribute__((noinline)) String plain(void) { return "plain"; }
__attribute__((unused)) static Var boxed(int x) { return x; }
__attribute__((unused)) static Array items = [1, 2];

_Noreturn void finish(int status);
void finish(int status) { exit(status); }

int main(void) {
  printf("%d %s %zu\n", plain().len(), Var.repr(boxed(7)), items.len());
  $scoped(__attribute__((unused)) Var value = 5, {
    printf("%s\n", Var.repr(value));
  });
  finish(3);
}
