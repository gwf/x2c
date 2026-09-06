#include "x2c.x"

#include <stdio.h>

static int old_seen;
static int new_seen;


static Symbol _observe_relabel(List errors, Var data) {
  (void) data;
  Symbol code = errors.last().list().assoc(<code>);
  if (code == <old-error>) old_seen++;
  if (code == <new-error>) {
    new_seen++;
    return <handled>;
  }
  return <declined>;
}


static void _relabel_nested_pattern(void) {
  try {
    List detail = cons(
      Symbol.var(<nested>),
      cons(String.var(String.new("marker")), NULL)
    );
    raise %(old-error (detail $detail));
  }
  catch %(old-error (detail (nested ${%"marker"}))):
    raise %(new-error);
}


int main(void) {
  Error.initialize();
  ErrorHandler observer = Error.push(_observe_relabel, void);
  _relabel_nested_pattern();
  Error.pop(observer);
  if (old_seen != 0 || new_seen != 1) return 1;
  puts("catch patterns initialize at registration");
  return 0;
}
