#!/usr/bin/env python3
"""Generates the match-component benchmark units for N in (50, 400):
m-plain-N.x, N functions with one four-arm static match each, built in;
m-comp-N.x, the same under the typed hook of match-component.x; and
m-hand-N.x, the if tests the component writes, spelled by hand."""
import os

here = os.path.dirname(os.path.abspath(__file__))


def arms(i):
    return f"""    case %(a{i} ?x ?y): return x.int() + y.int();
    case %(b{i} (c ?z) *rest): return z.int() + rest.len();
    case %(c{i} ?(String s)): return s.len();
    default: return 0;"""


def matched(i):
    return f"""int f{i}(List l) {{
  match (l) {{
{arms(i)}
  }}
  return -1;
}}"""


def hand(i):
    return f"""int f{i}(List l) {{
  List s = l, c0 = NULL, c1 = NULL;
  c0 = s;
  if (c0 && c0.car().u64 == ((Var) (<a{i}>)).u64) {{
    c0 = c0.cdr();
    if (c0) {{
      Var x = c0.car();
      c0 = c0.cdr();
      if (c0) {{
        Var y = c0.car();
        c0 = c0.cdr();
        if (!c0) return x.int() + y.int();
      }}
    }}
  }}
  c0 = s;
  if (c0 && c0.car().u64 == ((Var) (<b{i}>)).u64) {{
    c0 = c0.cdr();
    if (c0 && c0.car() is <list>) {{
      c1 = c0.car().list();
      if (c1 && c1.car().u64 == ((Var) (<c>)).u64) {{
        c1 = c1.cdr();
        if (c1) {{
          Var z = c1.car();
          c1 = c1.cdr();
          if (!c1) {{
            c0 = c0.cdr();
            List rest = c0;
            return z.int() + rest.len();
          }}
        }}
      }}
    }}
  }}
  c0 = s;
  if (c0 && c0.car().u64 == ((Var) (<c{i}>)).u64) {{
    c0 = c0.cdr();
    if (c0 && c0.car() is <string>) {{
      Var t = c0.car();
      c0 = c0.cdr();
      if (!c0) {{
        String text = t;
        return text.len();
      }}
    }}
  }}
  return 0;
}}"""


for n in (50, 400):
    units = {
        "m-plain": ["#include \"x2c.x\""] + [matched(i) for i in range(n)],
        "m-comp": ["#include \"match-component.x\""] +
                  [matched(i) for i in range(n)],
        "m-hand": ["#include \"x2c.x\""] + [hand(i) for i in range(n)],
    }
    for name, lines in units.items():
        with open(os.path.join(here, f"{name}-{n}.x"), "w") as f:
            f.write("\n".join(lines) + "\n")
