/*  leak.x -- package whose entry includes a foreign public surface. */
#pragma once
#include "../../leak-foreign.x"

int leak_total(void);


int leak_total(void) { return leak_base(); }
