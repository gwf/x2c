/*  with-rename.x -- `as` chooses the local spelling of a package member. */
#pragma once

import "geo" with Vec as Xvec;

double diagonal(double x, double y);


double diagonal(double x, double y) {
  Xvec v = Xvec.new(x, y);
  return v.norm();
}
