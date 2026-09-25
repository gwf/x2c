/*  tally.x -- a package with a compile-time part, for the native module
    probe. Its one bodyless `meta` prototype makes the package build a
    module, and its record class boxes as a Var inside the compiler.
*/
class Tally { int count; int total; };

meta int tally_sum(int n);
$(import "tally.xmacro")

#pragma private

int tally_sum(int n) {
  Var boxed = Tally.new(n, n * (n + 1) / 2);
  return boxed.tally().total;
}
