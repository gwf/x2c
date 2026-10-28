#!/usr/bin/env -S x2c script
int script_leaf(void) => 1;
int script_caller(void) => script_leaf();
printf("%d\n", script_caller());
