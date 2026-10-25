#include "x2c.x"

meta static List short_entry_rows(void) => %((map-entry "key"));

macro Entry $invalid_row() {
  @short_entry_rows()
}

Map values = %{ ${$invalid_row()} };
