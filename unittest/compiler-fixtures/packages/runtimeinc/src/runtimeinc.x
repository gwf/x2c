/*  runtimeinc.x -- package whose public and private parts include runtime
    modules. A runtime module keeps its own spellings, as an included C
    header does, and an include below #pragma private stays inside.
*/
#pragma once
#include "path.x"

int twice(int x);
Path home_path(void);

#pragma private

#include "string.x"

int twice(int x) { return 2 * x; }

Path home_path(void) { return "/home/runtime"; }
