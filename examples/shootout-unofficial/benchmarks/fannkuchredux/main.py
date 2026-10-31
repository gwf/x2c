#!/usr/bin/env python3

import sys


def fannkuchredux(n):
    permutation = list(range(n))
    working = [0] * n
    counts = [0] * n
    maximum = checksum = permutation_count = 0
    r = n

    while True:
        while r != 1:
            counts[r - 1] = r
            r -= 1

        working[:] = permutation
        flips = 0
        while working[0] != 0:
            end = working[0]
            working[: end + 1] = working[end::-1]
            flips += 1

        maximum = max(maximum, flips)
        checksum += flips if permutation_count % 2 == 0 else -flips

        while True:
            if r == n:
                return checksum, maximum
            first = permutation[0]
            permutation[:r] = permutation[1 : r + 1]
            permutation[r] = first
            counts[r] -= 1
            if counts[r] > 0:
                break
            r += 1
        permutation_count += 1


n = int(sys.argv[1]) if len(sys.argv) > 1 else 7
checksum, maximum = fannkuchredux(n)
print(checksum)
print(f"Pfannkuchen({n}) = {maximum}")
