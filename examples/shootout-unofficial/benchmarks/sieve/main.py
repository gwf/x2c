#!/usr/bin/env python3

import sys


limit, iterations = map(int, sys.argv[1:])
checksum = 0

for _ in range(iterations):
    prime = bytearray(b"\1") * (limit + 1)
    prime[0:2] = b"\0\0"
    for p in range(2, int(limit**0.5) + 1):
        if prime[p]:
            prime[p * p : limit + 1 : p] = b"\0" * (
                (limit - p * p) // p + 1
            )
    values = [n for n in range(2, limit + 1) if prime[n]]
    checksum = (checksum + values[-1] + len(values)) & 0xFFFFFFFF

print(checksum)
