/*  iterators.x -- lazy selection, merging, and validation */


int main(void) {
  Scope.retain();

  List seen = %(3 1 3 2 1 4);
  printf("unique: %s\n", seen.iter().unique().list().str());

  List urgent = %(101 102), routine = %(201 202 203);
  printf("queue: %s\n", urgent.iter()
    .chain(routine.iter()).head(4).list().str());

  printf("first square over threshold: %d\n", range(1, 20, 1)
    .map(%!(value) => value * value)
    .find(%!(value) => value > 70).int());

  List temperatures = %(71 106 98 112 87);
  printf("temperature alerts: %d\n", temperatures.iter()
    .filter(%!(value) => value > 100).count());
  printf("temperature warning: %s\n", temperatures.iter()
    .any(%!(value) => value > 110) ? "yes" : "no");

  List scores = %(91 88 100 73);
  printf("scores valid: %s\n", scores.iter()
    .all(%!(score) => score >= 0 && score <= 100) ? "yes" : "no");

  printf("numbered: %s\n", %(<parse> <compile> <link>).iter()
    .enumerate(1).list().str());

  Scope.release();
  return 0;
}
