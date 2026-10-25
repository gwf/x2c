#!/usr/bin/env x2c
#include "x2c.x"
auto static int twice(int n) { Array a = [n]; return a[0].int()*2; }
auto int next(int n) => n+1;
auto Array ordinary = [];
auto inferred = Buffer.new(0);
auto Scope destination = NULL;
auto (&destination) { ordinary.push(3); }
auto { printf("%d %d %d\n",twice(4),next(5),ordinary[0].int()); }
