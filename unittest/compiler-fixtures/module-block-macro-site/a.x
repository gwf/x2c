static int counter = 1;
static macro Expression $read.counter() => counter;
module int a_read(void) { return $read.counter(); }
