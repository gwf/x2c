#!/usr/bin/env python3
"""Writes delegate-N.x (one call through a delegate field per function) and
direct-N.x (the same call through the field, written out) for N in
(50, 400) into the current directory."""

HEAD = '''#include "x2c.x"

typedef struct Part { int value; } Part;
static int Part.read(Part part) { return part.value; }
typedef struct Owner { int other; delegate Part part; } Owner;
'''

DELEGATE = '''int f{i}(Owner owner) {{
  return owner.read() + {i};
}}'''

DIRECT = '''int f{i}(Owner owner) {{
  return owner.part.read() + {i};
}}'''

for n in (50, 400):
    for kind, body in (("delegate", DELEGATE), ("direct", DIRECT)):
        with open(f"{kind}-{n}.x", "w") as out:
            out.write(HEAD + "\n")
            out.write("\n\n".join(body.format(i=i) for i in range(n)))
            out.write("\n")
