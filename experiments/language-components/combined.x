#include "access/component.x"
#include "sequences/managed.x"
#include "dispatch/components.x"
#include "access/delegation.x"

typedef struct Batch { Array values; } Batch;
static Batch batch(int value) {
  Array values = [];
  values.push((uchar) value);
  return (Batch) {.values = values};
}
void Batch.cleanup(Batch value) {
  printf("cleanup %d\n", value.values[0].int());
  value.values.free();
}
macro Declaration $batch_initialization(Name $name, Expr $value) {
  Batch $name = $value;
}
$after_initialization($batch_initialization)
meta Code managed_batch(Code declaration) {
  match (declaration) case $batch_initialization(?name, ?value):
    return $!{ defer $name.cleanup(); };
  return NULL;
}
int main(void) {
  Batch first = batch(3), second = batch(first.values[0].int());
  Distance a = {2}, b = {4}, distance = a + b;
  Wrapper forwarded = {.part = {.value = 7}};
  printf("extensions %d %d\n", distance.value, forwarded.read(1));
  Choice choice = {1};
  switch (choice) { case 1: puts("choice"); break; }
  Var old = first.values[0]++;
  Var stored = (second.values[0] += 2);
  printf("combined %d %d\n", old.int(), stored.int());
  return 0;
}
