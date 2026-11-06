#!/usr/bin/env -S x2c script
int script_early(void) => 1;
printf("%d\n", script_early());
int script_late(void) => script_early();
