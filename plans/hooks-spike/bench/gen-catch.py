#!/usr/bin/env python3
"""Writes the catch benchmark units for N in (50, 400) into the current
directory. Each has N functions with one try whose four filtered arms are
static patterns: a flat literal detail, a final star, a keyed binder before
a star, and a bare code. In c-catch-N.x the first pattern differs in every
function; in c-same-N.x every function has the same four, so catches can
share a selector. Translation cost per use is the slope from 50 to 400."""


def function(i, literal):
    return f"""int f{i}(int mode) {{
  try {{
    if (mode == {i}) raise %(bad-arg (value {i}));
  }}
  catch %(bad-arg (value {literal})): return 1;
  catch %(not-found *detail): return detail.len();
  catch %(io-fail (path ?p) *): return p.str().len();
  catch %(bad-state): return 4;
  return 0;
}}"""


for n in (50, 400):
    for name, literal in (("c-catch", None), ("c-same", 7)):
        lines = ["#include \"x2c.x\""] + [
            function(i, i if literal is None else literal) for i in range(n)]
        with open(f"{name}-{n}.x", "w") as f:
            f.write("\n".join(lines) + "\n")
