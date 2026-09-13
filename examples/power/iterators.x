/*  iterators.x -- selection, merging, and validation over Lists */


int main(void) {
  Scope.retain();

  List seen = %(3 1 3 2 1 4);
  printf("unique: %s\n", seen.unique().str());

  List urgent = %(101 102), routine = %(201 202 203);
  printf("queue: %s\n", urgent.append(routine).head(4).str());

  int first_square = 0;
  foreach (Var value, range(1, 20, 1)) {
    int square = value.int() * value.int();
    if (square > 70) {
      first_square = square;
      break;
    }
  }
  printf("first square over threshold: %d\n", first_square);

  List temperatures = %(71 106 98 112 87);
  int alerts = 0;
  foreach (Var value, temperatures) if (value.int() > 100) alerts++;
  printf("temperature alerts: %d\n", alerts);
  printf("temperature warning: %s\n",
    temperatures.any(%!(value) => value > 110) ? "yes" : "no");

  List scores = %(91 88 100 73);
  printf("scores valid: %s\n",
    scores.all(%!(score) => score >= 0 && score <= 100) ? "yes" : "no");

  Array numbered = %[];
  int index = 1;
  foreach (Var stage, %(<parse> <compile> <link>))
    numbered.push(%(${index++} $stage));
  printf("numbered: %s\n", numbered.list_free().str());

  Scope.release();
  return 0;
}
