#!/usr/bin/env python3
"""Generates the hook-spike benchmark units for N in (50, 400)."""
import os

here = os.path.dirname(os.path.abspath(__file__))

# trace.x without its hook, for the explicit-decorator variant.
with open(os.path.join(here, "trace.x")) as f:
    text = f.read().replace("hook function $trace.body;\n", "")
with open(os.path.join(here, "trace-nohook.x"), "w") as f:
    f.write(text)


def labels(i):
    return f'case "a{i}": return 1;\n    case "b{i}": case "c{i}": return 2;\n    default: return 0;'


def switch_unit(kind, n):
    out = []
    if kind == "hook":
        out.append('#include "string-switch.x"')
    elif kind == "dec":
        out.append('#include "string-switch-orig.x"')
    elif kind == "dec2":
        out.append('#include "string-switch.x"')
    else:
        out.append('#include "x2c.x"')
    for i in range(n):
        if kind == "hand":
            out.append(f"""int f{i}(String s) {{
  {{
    String selected = s;
    switch (selected == "a{i}" ? 1 : selected == "b{i}" ? 2 : selected == "c{i}" ? 3 : 0) {{
      case 1: return 1;
      case 2: case 3: return 2;
      default: return 0;
    }}
  }}
  return -1;
}}""")
        else:
            head = "switch" if kind == "hook" else "$strings.switch"
            out.append(f"""int f{i}(String s) {{
  {head}(s) {{
    {labels(i)}
  }}
  return -1;
}}""")
    return "\n".join(out) + "\n"


def trace_unit(kind, n):
    out = ["#include <stdio.h>"]
    if kind == "hook":
        out.append('#include "trace.x"')
    elif kind == "dec":
        out.append('#include "trace-nohook.x"')
    for i in range(n):
        body = f"  int r = n + {i};\n  if (r > 1000) return 0;\n  return r;"
        if kind == "hand":
            out.append(f"""int t{i}(int n) {{
  const char *traced = __func__;
  printf("enter %s\\n", traced);
  defer printf("exit %s\\n", traced);
  {{
{body}
  }}
}}""")
        elif kind == "dec":
            out.append(f"""$trace.body() int t{i}(int n) {{
{body}
}}""")
        else:
            out.append(f"""int t{i}(int n) {{
{body}
}}""")
    return "\n".join(out) + "\n"


for n in (50, 400):
    for kind in ("hook", "dec", "dec2", "hand"):
        with open(os.path.join(here, f"sw-{kind}-{n}.x"), "w") as f:
            f.write(switch_unit(kind, n))
    for kind in ("hook", "dec", "hand", "plain"):
        with open(os.path.join(here, f"tr-{kind}-{n}.x"), "w") as f:
            f.write(trace_unit(kind, n))
