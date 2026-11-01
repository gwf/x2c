/* Optional fallback probe; run with run-task-backend.sh. */
#include "x2c.x"

int main(void) {
  Scope.open();
  defer Scope.close();
  Array synchronous = [17, 29];
  if (synchronous.len() != 2) return 1;
  int caught = 0, entered = 0;
  try Task.run([%!(void) using &entered => { entered++; return void; }]);
  catch %(bad-state (operation "Task.run")
                   (reason "native task backend unavailable")): caught++;
  try Task.run([]);
  catch %(bad-state (operation "Task.run")
                   (reason "native task backend unavailable")): caught++;
  return caught == 2 && entered == 0 ? 0 : 1;
}
