#include "x2c.x"

macro Expression $expression_result() => (1)

typedef struct InvalidExpressionResult {
  $expression_result();
} InvalidExpressionResult;
