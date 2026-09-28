#include "x2c.x"

// Identity fields can leave the aggregate unchanged when its syntax binds.
// Its tag identity must still reach the typedef and member lookup.
macro Unit $record() {
  $(quote ((typedef
    (struct (binding 9001 "GeneratedRecord")
      (fields (declare (int) (bindings (bind (binding 9003 "value") ())))))
    (bindings (bind (binding 9001 "GeneratedRecord") ())))))...
}

$record();

int main(void) {
  GeneratedRecord record = {.value = 17};
  printf("%d\n", record.value);
  return 0;
}
