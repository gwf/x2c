#!/usr/bin/env python3
"""Generates units applying $ident.tpl or $ident.meta to N switch bodies."""
import os

here = os.path.dirname(os.path.abspath(__file__))
for n in (50, 400):
    for kind in ("tpl", "meta"):
        out = ['#include "ident.x"']
        for i in range(n):
            out.append(f"""int f{i}(int s) {{
  $ident.{kind}() switch (s) {{
    case 1: return 1;
    case 2: case 3: return 2;
    default: return 0;
  }}
  return -1;
}}""")
        with open(os.path.join(here, f"id-{kind}-{n}.x"), "w") as f:
            f.write("\n".join(out) + "\n")
