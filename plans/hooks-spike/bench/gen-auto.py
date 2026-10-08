#!/usr/bin/env python3
"""Writes auto-N.x (one `$auto` declaration per function) and hand-N.x
(the same declaration with a hand-written `defer`) for N in (50, 400)
into the current directory."""

AUTO = '''int f{i}(int x) {{
  Array items = $auto([x, {i}]);
  return (int) items.len();
}}'''

HAND = '''int f{i}(int x) {{
  Array items = [x, {i}];
  defer items.cleanup();
  return (int) items.len();
}}'''

for n in (50, 400):
    for kind, body in (("auto", AUTO), ("hand", HAND)):
        with open(f"{kind}-{n}.x", "w") as out:
            out.write('#include "x2c.x"\n\n')
            out.write("\n\n".join(body.format(i=i) for i in range(n)))
            out.write("\n")
