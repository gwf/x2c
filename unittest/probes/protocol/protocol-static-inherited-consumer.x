#include "protocol-static-owner.x"

int static_consumer_total(StaticItemsChild values) {
  int total = 0;
  foreach(int value, values) total += value;
  return total;
}

// Both source transports must render cache identities locally in notes.
macro Expression $require_note_method(Expr $value) => $value.nope();

int literal_note(void) {
  return $require_note_method(%(binding 42 "literal data"));
}

int quotation_note(void) {
  return $require_note_method($!{ %(binding 42 "literal data"); });
}
