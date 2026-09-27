/*  func-call.x -- native compilation of direct captured Func calls

    Copyright (c) 2026 Gary William Flake.
*/

Func capture(int n) => %!(int x) => n+x;
int apply_capture(Func fn, int x) => fn(x);

int main(void) {
  Func plus = capture(7);
  Func no_args = %!(void) => 37;
  if (plus(5) != 12 || capture(19)(4) != 23 ||
      apply_capture(plus, 9) != 16 || no_args() != 37)
    return 1;
  return 0;
}
