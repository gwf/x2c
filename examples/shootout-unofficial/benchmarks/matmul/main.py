#!/usr/bin/env python3
import sys

n, runs = map(int, sys.argv[1:])
a = [(i * 31 + j * 17) % 100 / 100.0 for i in range(n) for j in range(n)]
b = [(i * 13 + j * 29) % 100 / 100.0 for i in range(n) for j in range(n)]
c = [0.0] * (n * n)
checksum = 0.0
for run in range(runs):
    for i in range(n):
        for j in range(n):
            c[i * n + j] = sum(
                a[i * n + k] * b[k * n + j] for k in range(n)
            )
    checksum += c[(run * 97) % len(c)]
print(f"{checksum:.9f}")
