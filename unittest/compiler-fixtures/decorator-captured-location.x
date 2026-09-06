#include "x2c.x"

macro Decorator $fixture.wrap(Statement $target) => {
  raise %(genloc);
  $target
}

static void decorated(void) {
  $fixture.wrap()
  raise %(caploc);
}

int main(void) {
  Error.initialize();
  Error.policy_set(<genloc>, <collect>);
  Error.policy_set(<caploc>, <collect>);
  int mark = Error.mark(), generated = 0, captured = 0;
  decorated();
  foreach(Var item, Error.since(mark)) {
    List entry = item;
    Symbol code = entry.assoc(<code>);
    int line = entry.assoc(<location>).list().assoc(<line>).integer();
    if (code == <genloc>) generated = line;
    if (code == <caploc>) captured = line;
  }
  printf("%d %d\n", generated, captured);
  return 0;
}
