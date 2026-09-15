#!/usr/bin/env -S x2c script
int total = 1;

static int twice(void) => total * 2;

printf("%d\n", twice());
