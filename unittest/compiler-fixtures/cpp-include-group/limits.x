#pragma once

// x2c cannot decide `__APPLE__`, so this include ends a segment inside an
// undecided group, and the next segment starts from a copy of the state.
#ifdef __APPLE__
#include <stddef.h>
#endif

#ifndef LIM_SIZE
#define LIM_SIZE 16
int lim_default(void);
#endif
