#!/usr/bin/env python3

import sys


def hash_byte(value, byte):
    return ((value << 5) + value + byte) & 0xFFFFFFFF


width, height, iterations = map(int, sys.argv[1:])
checksum = 5381

for _ in range(iterations):
    for byte in f"P4\n{width} {height}\n".encode("ascii"):
        checksum = hash_byte(checksum, byte)

    for y in range(height):
        bit_count = byte = 0
        for x in range(width):
            zr = zi = tr = ti = 0.0
            cr = 2.0 * x / width - 1.5
            ci = 2.0 * y / height - 1.0
            i = 0
            while i < 50 and tr + ti <= 4.0:
                zi = 2.0 * zr * zi + ci
                zr = tr - ti + cr
                tr = zr * zr
                ti = zi * zi
                i += 1
            byte = (byte << 1) | (tr + ti <= 4.0)
            bit_count += 1
            if bit_count == 8:
                checksum = hash_byte(checksum, byte)
                bit_count = byte = 0
        if bit_count:
            checksum = hash_byte(checksum, byte << (8 - bit_count))

print(checksum)
