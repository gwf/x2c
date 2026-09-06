/* other.x -- second package method for import ambiguity fixtures. */
#pragma once

int Var.vec(Var value);

#pragma private

int Var.vec(Var value) {
  return value.truthy();
}
