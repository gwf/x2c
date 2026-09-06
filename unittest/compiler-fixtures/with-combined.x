/*  with-combined.x -- `with` adds shortcuts without retiring the alias. */
#pragma once

import "geo" as g with Vec;

double outline(double x, double y);

#pragma private

double outline(double x, double y) {
  Vec v = Vec.new(x, y);
  g.VecPair pair;
  pair.a.x = x; pair.a.y = 0.0;
  pair.b.x = 0.0; pair.b.y = y;
  return v.norm() + g.span(pair);
}
