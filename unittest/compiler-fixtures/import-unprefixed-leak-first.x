/*  import-unprefixed-leak-first.x -- the package walks its foreign unit
    before the consumer includes it. The unit keeps its own spellings, so
    the import reports the leak as it does when the consumer came first. */
#pragma once

import "leak";
#include "packages/leak-foreign.x"

int consume(void);

#pragma private

int consume(void) { return leak.leak_total() + leak_base(); }
