#pragma once
#include "include-recursion-b.h"

static inline RecursionPair recursion_pair(int value) {
  RecursionPair pair;
  pair.value = recursion_double(value);
  return pair;
}
