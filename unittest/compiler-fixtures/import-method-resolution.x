/* import-method-resolution.x -- local methods win; aliases stay explicit. */
#pragma once

import "geo" as g;
import "other" as o;

typedef Var Packed;

g.Vec geo_vec(Var value);
int other_vec(Var value);
int local_vec(Packed value);

#pragma private

static int Var.vec(Var value) {
  return value.truthy() + 7;
}

g.Vec geo_vec(Var value) {
  return g.Var_vec(value);
}

int other_vec(Var value) {
  return o.Var_vec(value);
}

int local_vec(Packed value) {
  return value.vec();
}
