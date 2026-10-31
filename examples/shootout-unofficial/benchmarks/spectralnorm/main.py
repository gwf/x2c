#!/usr/bin/env python3

from math import sqrt
import sys


def eval_a(i, j):
    ij = i + j
    return 1.0 / (ij * (ij + 1) // 2 + i + 1)


def eval_a_times_u(vector):
    return [
        sum(eval_a(i, j) * value for j, value in enumerate(vector))
        for i in range(len(vector))
    ]


def eval_at_times_u(vector):
    return [
        sum(eval_a(j, i) * value for j, value in enumerate(vector))
        for i in range(len(vector))
    ]


def eval_ata_times_u(vector):
    return eval_at_times_u(eval_a_times_u(vector))


n = int(sys.argv[1]) if len(sys.argv) > 1 else 100
u = [1.0] * n
for _ in range(10):
    v = eval_ata_times_u(u)
    u = eval_ata_times_u(v)
v_bv = sum(left * right for left, right in zip(u, v))
vv = sum(value * value for value in v)
print(f"{sqrt(v_bv / vv):.9f}")
