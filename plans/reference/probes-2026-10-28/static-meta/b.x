#pragma once
meta static int hidden(int n) => n + 20;
meta static int state = 200;
macro Expression $b_kept() using hidden => $hidden(3);
enum { B = $hidden(1), B_MACRO = $b_kept() };
meta int b_public(void) => hidden(2);
meta int b_state(void) => ++state;
