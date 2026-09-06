/*  geovar.x -- Var boxing and protocol adoption inside the geo package. */
#pragma once
#include "geo.x"

double roundtrip_norm(double x, double y);

#pragma private

double roundtrip_norm(double x, double y) {
  Vec v = Vec.new(x, y);
  Var boxed = v;
  Vec back = boxed.vec();
  return back.norm();
}
