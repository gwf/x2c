/*  with-basic.x -- `with` binds a package member to a bare spelling.

    The local spelling is the only thing that changes: every generated C
    name still carries the package's own geo__ prefix.
*/
#pragma once

import "geo" with Vec;

double diagonal(double x, double y);

#pragma private

double diagonal(double x, double y) {
  Vec v = Vec.new(x, y);
  return v.norm();
}
