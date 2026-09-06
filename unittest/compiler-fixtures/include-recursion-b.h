#pragma once

typedef struct {
  int value;
} RecursionPair;

static inline int recursion_double(int x) {
  return 2 * x;
}
