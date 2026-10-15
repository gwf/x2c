#pragma once

inline int second_inline_record(void) {
  struct Record { int count; } value = {42};
  Func f = %!() using &value => ++value.count;
  return f().int();
}
