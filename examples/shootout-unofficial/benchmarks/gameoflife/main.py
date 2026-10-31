#!/usr/bin/env python3
import sys

w, h, steps = map(int, sys.argv[1:])
cells = [(i * 17 + i // w * 23) % 11 == 0 for i in range(w * h)]
for _ in range(steps):
    nxt = [False] * len(cells)
    for y in range(h):
        for x in range(w):
            neighbors = sum(
                cells[((y + dy) % h) * w + (x + dx) % w]
                for dy in (-1, 0, 1)
                for dx in (-1, 0, 1)
                if dx or dy
            )
            i = y * w + x
            nxt[i] = neighbors == 3 or (cells[i] and neighbors == 2)
    cells = nxt
value = 2166136261
for alive in cells:
    value = ((value ^ alive) * 16777619) & 0xFFFFFFFF
print(value)
