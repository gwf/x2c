#!/usr/bin/env python3
import csv
import io
import sys

rows, runs = map(int, sys.argv[1:])
text = "".join(
    f'"point {i}, sample",{(i % 101) / 7:.6f},,'
    f'{(i % 97) / 11:.6f},"tag {i % 13}",{(i % 89) / 5:.6f}\n'
    for i in range(rows)
)
checksum = 0.0
for _ in range(runs):
    checksum += sum(
        float(row[1]) + float(row[3]) + float(row[5])
        for row in csv.reader(io.StringIO(text))
    )
print(f"{checksum:.6f}")
