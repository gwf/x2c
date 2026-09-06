/*  import-package-surface.x -- a package's members and adoptions cross.

    The consumer reads a field through the package's pointer typedef and
    iterates a package type through the Iter adoption the package declares.
*/
#pragma once

import "geo" as g;

typedef Var Packed;

double first_component(double x, double y);
g.ChainLeaf package_tail(g.ChainLeaf values);
int package_tail_len(g.ChainLeaf values);

#pragma private

double first_component(double x, double y) {
  g.Vec v = g.Vec.new(x, y);
  Packed boxed = v;
  g.Vec roundtrip = boxed.vec();
  double total = roundtrip.x;
  foreach(Var part, v) total += part.floating();
  return total;
}

g.ChainLeaf package_tail(g.ChainLeaf values) {
  return values.rest();
}

int package_tail_len(g.ChainLeaf values) {
  return values.rest().leaf_len();
}
