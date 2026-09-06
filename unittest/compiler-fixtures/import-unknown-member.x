/*  import-unknown-member.x -- the alias resolves, the member does not. */
#pragma once

import "geo" as g;

double missing(void);

#pragma private

double missing(void) { return g.frobnicate(); }
