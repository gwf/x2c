#!/usr/bin/env -S x2c script
// A Unit macro introduces main after a statement was retained.
puts("statement");
macro Unit $entry(Name $name) { int $name(void) { return 0; } }
$entry(main);
