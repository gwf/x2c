/*  leak.x -- package whose foreign surface sits above #pragma private. */
#pragma once
#include "../../leak-foreign.x"

int leak_total(void);

#pragma private

int leak_total(void) { return leak_base(); }
