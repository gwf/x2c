#include "x2c.x"

macro Decorator $fixture.wrap(Statement $target) => {
  raise %(genloc);
  $target
}

static void decorated(void) {
  $fixture.wrap()
  raise %(caploc);
}

static int generated, captured;

static Symbol record_line(List errors, Var data) {
  (void) data;
  List entry = errors.last();
  Symbol code = entry.assoc(<code>);
  int line = entry.assoc(<location>).list().assoc(<line>).integer();
  if (code == <genloc>) generated = line;
  if (code == <caploc>) captured = line;
  return <handled>;
}

int main(void) {
  Error.initialize();
  ErrorHandler observer = Error.push(record_line, void);
  decorated();
  Error.pop(observer);
  printf("%d %d\n", generated, captured);
  return 0;
}
