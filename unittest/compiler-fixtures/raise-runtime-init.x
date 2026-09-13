#include "x2c.x"

#include <stdio.h>

int main(void) {
  Error.initialize();
  Error.policy_set(<runtime-in>, <collect>);
  int mark = Error.mark();
  raise %(runtime-in
          (detail (nested ${%"marker"})));
  List entry = Error.since(mark).car();
  List detail = entry.assoc(<detail>);
  List nested = detail.car().list().cadr();
  (Symbol tag, String value) = nested;
  printf("%s %s\n",
         tag.str(), value);
  return 0;
}
