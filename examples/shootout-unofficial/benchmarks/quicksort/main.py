#!/usr/bin/env python3
import sys

n, runs = map(int, sys.argv[1:])
state = 1
data = []
for _ in range(n):
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
    data.append(state & 0x7FFFFFFF)
checksum = 0


def quicksort(a, left, right):
    i, j = left, right
    pivot = a[(left + right) // 2]
    while i <= j:
        while a[i] < pivot:
            i += 1
        while a[j] > pivot:
            j -= 1
        if i <= j:
            a[i], a[j] = a[j], a[i]
            i += 1
            j -= 1
    if left < j:
        quicksort(a, left, j)
    if i < right:
        quicksort(a, i, right)


for run in range(runs):
    copy = data.copy()
    quicksort(copy, 0, n - 1)
    checksum = (checksum + copy[(run * 97) % n]) & 0xFFFFFFFF
print(checksum)
