#include "x2c.x"

/* A private `extern` declares storage defined elsewhere. It stays a
   declaration in the generated source; a definition would shadow the
   process environment with a null tentative definition. */

#pragma private

extern char **environ;

int main(void) {
  printf("environment %s\n", environ && environ[0] ? "visible" : "missing");
  return 0;
}
