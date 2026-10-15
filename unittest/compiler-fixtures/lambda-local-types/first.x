#pragma once

inline int first_inline_record(void) {
  struct Record { int count; } value = {41};
  Func f = %!() using &value => ++value.count;
  return f().int();
}
