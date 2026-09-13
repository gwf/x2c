#include "x2c.x"

#include <stdio.h>

static List observed;

static Symbol observe_newest(List errors, Var data) {
  (void) data;
  observed = Error.snapshot(errors.last());
  return <handled>;
}

int main(void) {
  Error.initialize();
  ErrorHandler observer = Error.push(observe_newest, void);
  raise %(runtime-in
          (detail (nested ${%"marker"})));
  Error.pop(observer);
  List entry = observed;
  List detail = entry.assoc(<detail>);
  List nested = detail.car().list().cadr();
  (Symbol tag, String value) = nested;
  printf("%s %s\n",
         tag.str(), value);
  return 0;
}
