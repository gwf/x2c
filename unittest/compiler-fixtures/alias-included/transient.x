#pragma once
#include "x2c.x"

/* Uses an alias for its own declarations, then removes it, so including
   files never see it. */
alias 40 + 2 as answer;
extern int transient_value[answer];
unalias answer;
