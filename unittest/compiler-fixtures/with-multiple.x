/*  with-multiple.x -- several members, one renamed, one a free function. */
#pragma once

import "geo" with Vec as Xvec, VecPair, span;

double outline(double x, double y);

#pragma private

double outline(double x, double y) {
  Xvec v = Xvec.new(x, y);
  VecPair pair;
  pair.a.x = x; pair.a.y = 0.0;
  pair.b.x = 0.0; pair.b.y = y;
  return v.norm() + span(pair);
}
