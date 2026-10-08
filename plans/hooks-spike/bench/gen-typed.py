#!/usr/bin/env python3
"""Generates the typed-hook benchmark units for N in (50, 400):
sw-typed-N.x, the gen.py String switch unit with plain `switch` statements
under the typed hook of typed-switch.x, and int-plain-N.x and
int-typed-N.x, the same shape over an int subject, which the hook
declines."""
import os

here = os.path.dirname(os.path.abspath(__file__))


def unit(include, subject, labels, n):
    out = [f'#include "{include}"']
    for i in range(n):
        a, b, c = labels(i)
        out.append(f"""int f{i}({subject} s) {{
  switch (s) {{
    case {a}: return 1;
    case {b}: case {c}: return 2;
    default: return 0;
  }}
  return -1;
}}""")
    return "\n".join(out) + "\n"


def strings(i):
    return f'"a{i}"', f'"b{i}"', f'"c{i}"'


def ints(i):
    return 3 * i, 3 * i + 1, 3 * i + 2


for n in (50, 400):
    units = {
        "sw-typed": unit("typed-switch.x", "String", strings, n),
        "int-plain": unit("x2c.x", "int", ints, n),
        "int-typed": unit("typed-switch.x", "int", ints, n),
    }
    for name, text in units.items():
        with open(os.path.join(here, f"{name}-{n}.x"), "w") as f:
            f.write(text)
