/*  with-unknown-name.x -- a `with` name must be a package export. */
#pragma once

import "geo" with Vec, NoSuchType;

double zero(void);


double zero(void) { return 0.0; }
