/*  meta-folding.x -- answering a constant call from the compile-time form

    A `meta` function has two forms, and where they agree the compiler may
    use either one. This unit's generated C is part of what the fixture owns,
    because the answer is the same either way: only the C says which form
    produced it. See `plans/meta-functions.md`.
*/

#include "x2c.x"

/* The milestone: both forms agree, so a call whose arguments are all
   compile-time constants emits the answer and the same call with a local
   emits a call. */
meta int mf_poly(int x) => x * x + 3 * x + 1;

/* A constant argument is not only a number. A `String` literal and a quoted
   `List` are the folded constants the lowering already reads back out of the
   compiler's literal cache. */
meta static int mf_width(String text, List extra) =>
  text.len() + extra.len();

/* A `String` result is left alone. The call returns a value its caller owns
   and may free; an interned literal is not one, so substituting it would
   change what the program is allowed to do with the answer. */
meta static String mf_label(int n) => %"row-$n";

/* A narrow or unsigned result is left alone for the same reason: the
   literal a fold would substitute is an `int`, and writing the conversion
   out is not what an author wrote. The answers are equal either way. */
meta static short mf_narrow(int n) => (short) (n * 30000);

int main(void) {
  int seven = 7, one = 1;
  String text = "abcd";
  printf("poly    %d %d\n", mf_poly(7), mf_poly(seven));
  printf("width   %d %d\n", mf_width("abcd", %(a b)), mf_width(text, %(a b)));
  printf("label   %s\n", mf_label(4));
  printf("narrow  %d %d\n", mf_narrow(3), mf_narrow(one + 2));
  return 0;
}
