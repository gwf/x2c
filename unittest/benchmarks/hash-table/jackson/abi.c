#include "x2c.h"

Var x2c_benchmark_uint_var(unsigned value)
{
  return uint_var(value);
}

Var x2c_benchmark_pointer_var(void *pointer)
{
  return Bytes_var((Bytes) pointer);
}

Var x2c_benchmark_string_var(const char *string)
{
  return String_var(String_new(string));
}

String x2c_benchmark_string(const char *string)
{
  return String_new(string);
}

char *x2c_benchmark_string_value(Var value)
{
  return Var_string(value);
}
