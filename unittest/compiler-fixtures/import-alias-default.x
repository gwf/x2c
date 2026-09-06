/*  import-alias-default.x -- an import without 'as' names the package. */
#pragma once

import "geo";

double diagonal(double x, double y);

#pragma private

double diagonal(double x, double y) {
  geo.Vec v = geo.Vec.new(x, y);
  return v.norm();
}
