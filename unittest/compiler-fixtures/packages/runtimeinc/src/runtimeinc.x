/*  runtimeinc.x -- package whose public and private parts include runtime
    modules. A runtime module keeps its own spellings, as an included C
    header does. All source includes expose their public declarations.
*/
#pragma once
#include "path.x"

int twice(int x);
Path home_path(void);


#include "string.x"

int twice(int x) { return 2 * x; }

Path home_path(void) { return "/home/runtime"; }
