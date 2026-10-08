#!/usr/bin/env python3
"""Generates sw-typed-N.x for N in (50, 400): the gen.py switch unit with
plain `switch` statements under the typed-phase hook of typed-switch.x."""
import os

here = os.path.dirname(os.path.abspath(__file__))

for n in (50, 400):
    out = ['#include "typed-switch.x"']
    for i in range(n):
        out.append(f"""int f{i}(String s) {{
  switch (s) {{
    case "a{i}": return 1;
    case "b{i}": case "c{i}": return 2;
    default: return 0;
  }}
  return -1;
}}""")
    with open(os.path.join(here, f"sw-typed-{n}.x"), "w") as f:
        f.write("\n".join(out) + "\n")
