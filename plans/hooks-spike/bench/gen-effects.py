#!/usr/bin/env python3
"""Generates the one-layer string-switch units for N in (50, 400) beside
itself. Run it in a scratch directory that also holds `string-switch.x`
and the two-layer version from 04a6fbeb as `string-switch-old.x`, then
measure each `sw-KIND-N.x` with measure.sh."""
import os

here = os.path.dirname(os.path.abspath(__file__))

LABELS = '''case "a{i}": return 1;
    case "b{i}": case "c{i}": return 2;
    default: return 0;'''

HAND = '''int f{i}(String s) {{
  {{
    String selected = s;
    switch (selected == "a{i}" ? 1 : selected == "b{i}" ? 2 : selected == "c{i}" ? 3 : 0) {{
      case 1: return 1;
      case 2: case 3: return 2;
      default: return 0;
    }}
  }}
  return -1;
}}'''

# kind -> (include, switch head)
KINDS = {
    "hand": ('"x2c.x"', None),
    "old-dec": ('"string-switch-old.x"', "$strings.string_switch(s)"),
    "old-switch": ('"string-switch-old.x"', "$strings.switch(s)"),
    "old-hook": ('"string-switch-old.x"', "switch (s)"),
    "new-switch": ('"string-switch.x"', "$strings.switch(s)"),
    "new-hook": ('"string-switch.x"', "switch (s)"),
}

for n in (50, 400):
    for kind, (include, head) in KINDS.items():
        out = [f"#include {include}"]
        for i in range(n):
            if head is None:
                out.append(HAND.format(i=i))
            else:
                body = LABELS.format(i=i)
                out.append(f"int f{i}(String s) {{\n  {head} {{\n    {body}\n  }}\n  return -1;\n}}")
        with open(os.path.join(here, f"sw-{kind}-{n}.x"), "w") as f:
            f.write("\n".join(out) + "\n")
