#include "x2c.x"
#include <stdio.h>

typedef struct MacroMemberName {
  int value;
} MacroMemberName;

macro Expression $read_member(Expr $record, Name $member) => (
  $record.$member
)

macro Expression $read_pointer_member(Expr $record, Name $member) => (
  $record->$member
)

int main(void) {
  MacroMemberName record = { .value = 42 }, *pointer = &record;
  int direct = $read_member(record, value);
  int indirect = $read_pointer_member(pointer, value);
  printf("%d %d\n", direct, indirect);
  return direct == 42 && indirect == 42 ? 0 : 1;
}
