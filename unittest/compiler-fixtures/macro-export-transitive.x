// Public definitions cross transitive includes. A later local macro
// replaces the included definition for subsequent source.
#include "macro-export-mid.x"

int delivered = $m.value() + mid_value;
int summed = $m_sum(1);

macro Expression $m.value() => 8;

int replaced = $m.value();
