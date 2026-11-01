#!/usr/bin/env x2c
#include "x2c.x"
int with(int n) { return n + 1; }
int value = 0;
try value = with(2);
finally { value++; }
with(4);
printf("script %d\n", value);
