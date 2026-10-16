#!/usr/bin/env -S x2c script
// Retained statements parse after file-scope macro definitions finish.
int value = $later();
macro Expression $later() => 17;
#define ENABLED 1
#if ENABLED
static int twice(int value) => value * 2;
value = twice(value);
#else
value = 0;
#endif
printf("value=%d\n", value);
