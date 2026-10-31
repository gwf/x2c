meta static int calls = 0;

meta static List rows(void) {
  calls++;
  return %(("counted_answer" 42) ("counted_other" 7));
}

meta static int read_calls(void) { return calls; }

expand $rows()
macro Declaration(Name $name, Expr $value) {
  int $name(void) { return $value; }
}

expand %()
macro Declaration(Name $name) { int $name(void) { return 0; } }

int main(void) {
  printf("%d %d %d\n", counted_answer(), counted_other(), $read_calls());
  return $read_calls() != 1;
}
