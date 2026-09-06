/*  with-collision.x -- a `with` name may not take a declared spelling. */
#pragma once

typedef struct Grid { double span; } Grid;

import "geo" with Vec as Grid;

double zero(void);

#pragma private

double zero(void) { return 0.0; }
