// An exported import reaches a file that includes the exporting file
// through another include, and a later definition in the includer replaces
// the delivered macro for the source after it.
#include "macro-export-mid.x"

int delivered = $m.value() + mid_value;
int summed = $m_sum(1);

macro Expression $m.value() => 8;

int replaced = $m.value();
