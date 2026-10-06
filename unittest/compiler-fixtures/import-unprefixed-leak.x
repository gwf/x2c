/*  import-unprefixed-leak.x -- the package's foreign unit escapes its
    name__ space because the consumer already collected it unprefixed. */
#pragma once
#include "packages/leak-foreign.x"

import "leak";

int consume(void);


int consume(void) { return leak.leak_total(); }
