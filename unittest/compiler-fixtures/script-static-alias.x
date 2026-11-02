#!/usr/bin/env -S x2c script

static int total = 3;
alias total * 2 as twice;
printf("%d\n", twice);
total = 4;
printf("%d\n", twice);
