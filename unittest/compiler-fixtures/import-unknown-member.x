/*  import-unknown-member.x -- the alias resolves, the member does not. */
#pragma once

import "geo" as g;

double missing(void);


double missing(void) { return g.frobnicate(); }
