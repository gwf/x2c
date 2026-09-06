/*  with-shadowed.x -- a block local outranks a `with` name. */
#pragma once

import "geo" with Vec, span;

double local_span(double x, double y);

#pragma private

double local_span(double x, double y) {
  Vec v = Vec.new(x, y);
  double span = v.norm();
  return span;
}
