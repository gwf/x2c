#include "x2c.x"
macro Statement $declare(Name $name) { String $name = "abc"; }
macro Statement $length(Name $out) { $declare(value); $out = value.len(); }
int main(void) { int out = 0; $length(out); printf("%d\n", out); }
