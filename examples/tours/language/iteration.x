#include "system-macros.x"

/* foreach converts each item to the declared type. try_get reports presence
   separately from its output: a stored zero is still a present value. */
int main(void) {
  List numbers = %(1 2 3 4);
  int total = 0;
  foreach (int n in numbers) {
    if (n == 2) continue;
    total += n;
  }
  (int first, String label) = %(7 "seven");
  Map counts = {zero: 0};
  Var found;
  int present = counts.try_get(<zero>, found);
  puts($dedent(%"
    Sum after skipping 2: $total
    Unpacked number: $first
    Unpacked label: $label
    Zero key present: $present
    Stored value: $found
    Missing key present: $(<missing> in counts)"));
  // False does not mean absent: empty containers and numeric zero are false.
  Array empty = [];
  printf("Empty array is true: %d\nNull differs from void: %d\n",
         empty ? 1 : 0, (Var) NULL !== void);
  return 0;
}
