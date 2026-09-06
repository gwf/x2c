/*  import-alias-shadow.x -- a local named 'g' outranks the package alias. */
#pragma once

import "geo" as g;

typedef struct Grid { double span; } Grid;

double local_span(void);

#pragma private

double local_span(void) {
  Grid g;
  g.span = 2.0;
  return g.span;
}
