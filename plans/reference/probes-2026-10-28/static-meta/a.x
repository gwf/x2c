#pragma once
meta static int hidden(int n) => n + 10;
meta static int state = 100;
macro Expression $a_kept() using hidden => $hidden(3);
enum { A = $hidden(1), A_MACRO = $a_kept() };
meta int a_public(void) => hidden(2);
meta int a_state(void) => ++state;
