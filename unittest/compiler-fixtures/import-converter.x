/*  import-converter.x -- a package converter serves a mixed operand.

    `2.0 * v` converts the double through geo's `double.vec`, which the
    consumer never spells; the generated C calls geo__double_vec.
*/
import "geo" with Vec;

int main(void) {
  Vec v = Vec.new(3.0, 4.0);
  Vec scaled = 2.0 * v;
  Var boxed = scaled;
  return boxed.vec().norm() > 9.9 ? 0 : 1;
}
