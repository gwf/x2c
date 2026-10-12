/* A rule registered after initialization adds statements after every
   initialized declaration its pattern matches, without replacing the
   declaration or moving its binding. */

#include "x2c.x"
#include "meta.x"

#include <stdio.h>

typedef struct Tracked { int value; } Tracked;

static void Tracked.cleanup(Tracked value) {
  printf("cleanup %d\n", value.value);
}

static Tracked make(int value) => (Tracked) { value };

macro Declaration $tracked_initialization(Name $name, Expr $value) {
  Tracked $name = $value;
}

meta Code register_after(Code function, Code pattern) =>
  function.register_after_initialization(pattern.value(), NULL);

macro Decorator $after_initialization(Unit $function, Expr $pattern) {
  @register_after($function, $pattern)
}

$after_initialization($tracked_initialization)
/* Each initialized Tracked local releases at block exit. */
meta Code managed_binding(Code declaration) {
  match (declaration) case $tracked_initialization(?name, ?value):
    return $!{ defer $name.cleanup(); };
  return NULL;
}

int main(void) {
  Tracked first = make(2), second = make(first.value + 1);
  int plain = 3;
  printf("%d %d %d\n", first.value, second.value, plain);
  return 0;
}
