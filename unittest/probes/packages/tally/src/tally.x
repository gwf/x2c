/*  tally.x -- a package with a compile-time part, for the native module
    probe. Its one bodyless `meta` prototype makes the package build a
    module, and its record class boxes as a Var inside the compiler.
*/
class Tally { int count; int total; };

meta int tally_sum(int n);
$(import "tally.xmacro")

#pragma private

int tally_sum(int n) {
  Func triangle = %!(int value) => value * (value + 1) / 2;
  Var boxed = Tally.new(n, triangle(n));
  return boxed.tally().total;
}
