#pragma once
#include "include-cycle-live-peer.x"

/* The peer includes this unit again. The host preprocessor must splice it
   once, or the parser sees each enumerator twice. */
enum {
  CYCLE_FIRST = 3,
  CYCLE_SECOND
};

CycleValue cycle_value(void) {
  return CYCLE_SECOND;
}
