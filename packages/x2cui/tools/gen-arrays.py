#!/usr/bin/env python3
"""Writes the x2c forms of the CUI functions that take arrays.

    python3 tools/gen-arrays.py deps/include/cui/cui.h

A function in cui.h whose first parameter is `cui_ctx *` and which has no
`$cui.method` row and no hand-written method in src/x2cui.x takes an array
of records, numbers, or flags. This tool writes, between markers:

    src/x2cui.x         one `Ui` method, which takes each array as a pointer
                        and its count as CUI declares them
    src/x2cui-arrays.x  one `$cui.` macro, which takes each array itself
                        and supplies its count with `$cui.count`

It keeps CUI's parameter names. Rerun it after changing the pinned CUI
version and review the difference. Variadic functions get no form.
"""
import re
import sys

BEGIN = "/* gen-arrays: begin generated %s */"
END = "/* gen-arrays: end generated %s */"

# No method: these return through pointers to pointers, or are variadic.
SKIP = {"cui_signature_points"}
# The parameter after the array that holds its count, where it is not the
# next one. diff_view_rows takes the first row, then the capacity.
COUNT_AFTER = {("cui_diff_view_rows", "rows"): "cap"}
# Arrays whose count is another parameter's: no count of their own.
SHARED = {("cui_toggle_group_ex", "values"),
          ("cui_multi_select_ex", "selected"),
          ("cui_blame_ex", "line_commit"), ("cui_heatmap_ex", "values")}


def prototypes(header):
  text = re.sub(r"/\*.*?\*/", "", header, flags=re.S).replace("\\\n", " ")
  pattern = (r"CUI_API\s+([^;{]*?)\b(cui_\w+)\s*\(([^;]*?)\)"
             r"\s*(?:CUI_PRINTF\([^)]*\))?\s*;")
  for match in re.finditer(pattern, text, flags=re.S):
    result = " ".join(match.group(1).split())
    params = [" ".join(p.split()) for p in match.group(3).split(",")]
    yield result, match.group(2), params


def split(param):
  match = re.match(r"(.*?)(\w+)$", param)
  return match.group(1).strip(), match.group(2)


def wrap(head, parts, tail, indent="  "):
  """Joins comma-separated parts onto lines of at most 79 columns."""
  one = head + ", ".join(parts) + tail
  if len(one) <= 79:
    return one
  lines, line = [head.rstrip()], indent
  for index, part in enumerate(parts):
    piece = part + (", " if index + 1 < len(parts) else tail)
    if len(line) + len(piece.rstrip()) > 79 and line.strip():
      lines.append(line.rstrip())
      line = indent
    line += piece
  lines.append(line.rstrip())
  return "\n".join(lines)


def classify(name, params):
  """Returns (x2c parameters, C arguments, macro holes, macro arguments)."""
  declared, passed, holes, given = [], [], [], []
  rest = [split(p) for p in params[1:]]
  index = 0
  while index < len(rest):
    ctype, pname = rest[index]
    after = rest[index + 1] if index + 1 < len(rest) else ("", "")
    after2 = rest[index + 2] if index + 2 < len(rest) else ("", "")
    consumed = 1
    if ctype == "const char *":
      declared.append(f"String {pname}")
      passed.append(pname)
    elif re.match(r"const cui_\w+_opts \*$", ctype):
      declared.append(f"{ctype[6:-2]} {pname}")
      passed.append(f"&{pname}")
    elif ctype == "char *" and after[0] == "size_t":
      declared.append(f"TextField {pname}")
      passed += [f"x2cui_buffer({pname})", f"{pname}.capacity"]
      consumed = 2
    elif ctype == "const char *const *" and after[0] == "int":
      declared.append(f"List {pname}")
      passed += [f"x2cui_strings({pname})", f"{pname}.len()"]
      consumed = 2
    elif ctype == "const char *const *":
      declared.append(f"List {pname}")
      passed.append(f"x2cui_strings({pname})")
    elif "*" in ctype and (name, pname) in SHARED:
      declared.append(f"{ctype}{pname}")
      passed.append(pname)
    elif "*" in ctype and (name, pname) in COUNT_AFTER:
      counter = COUNT_AFTER[(name, pname)]
      declared.append(f"{ctype}{pname}")
      passed.append(pname)
      holes.append(pname)
      given.append("$" + pname)
      index += 1
      while rest[index][1] != counter:
        declared.append(f"{rest[index][0]} {rest[index][1]}")
        passed.append(rest[index][1])
        holes.append(rest[index][1])
        given.append("$" + rest[index][1])
        index += 1
      declared.append(f"{rest[index][0]} {rest[index][1]}")
      passed.append(rest[index][1])
      given.append(f"$cui.count(${pname})")
      index += 1
      continue
    elif ("*" in ctype and after[0] == "int *" and after2[0] == "int"
          and after2[1] == "capacity"):
      # An array the user grows: its live count, then its capacity.
      declared += [f"{ctype}{pname}", f"int &{after[1]}", "int capacity"]
      passed += [pname, f"&{after[1]}", "capacity"]
      holes += [pname, after[1]]
      given += ["$" + pname, "$" + after[1], f"$cui.count(${pname})"]
      index += 3
      continue
    elif "*" in ctype and after[0] in ("int", "size_t"):
      declared += [f"{ctype}{pname}", f"{after[0]} {after[1]}"]
      passed += [pname, after[1]]
      holes.append(pname)
      given += ["$" + pname, f"$cui.count(${pname})"]
      index += 2
      continue
    elif "*" in ctype and not ctype.startswith("const "):
      declared.append(f"{ctype[:-1].strip()} &{pname}")
      passed.append(f"&{pname}")
    else:
      declared.append(f"{ctype} {pname}".replace("* ", "*"))
      passed.append(pname)
    holes.append(pname)
    given.append("$" + pname)
    index += consumed
  return declared, passed, holes, given


def forms(header, existing):
  methods, macros = [], []
  for result, name, params in prototypes(header):
    if not params[0].startswith("cui_ctx *") or name in existing:
      continue
    if name in SKIP or "..." in params or any("va_list" in p for p in params):
      continue
    short = name[4:-3] if name.endswith("_ex") else name[4:]
    declared, passed, holes, given = classify(name, params)
    counted = any("$cui.count" in g for g in given)
    if result == "const char *":
      result = "String"
    note = (f" Each array is a pointer and its count;\n"
            f"    `$cui.{short}` takes the array itself.\n*/"
            if counted else " */")
    methods.append(
      f"/** Calls `{name}`.{note}\n"
      + wrap(f"inline {result} Ui.{short}(", ["Ui ui"] + declared, ") =>")
      + "\n" + wrap(f"  {name}(", ["ui"] + passed, ");", "    ") + "\n")
    if not counted:
      continue
    kind = "Stmt" if result == "void" else "Expression"
    head = wrap(f"macro {kind} $cui.{short}(",
                ["Expr $ui"] + ["Expr $" + h for h in holes],
                ") {" if result == "void" else ") =>")
    call = wrap(f"  $ui.{short}(", given, ");", "    ")
    body = f"{head}\n{call}\n" + ("}\n" if result == "void" else "")
    macros.append(f"/** Calls `Ui.{short}` with the count of each array. */\n"
                  + body)
  return methods, macros


def replace(path, kind, items):
  source = open(path).read()
  begin, end = BEGIN % kind, END % kind
  start, stop = source.index(begin), source.index(end)
  body = begin + "\n\n" + "\n".join(items) + "\n"
  open(path, "w").write(source[:start] + body + source[stop:])


def main():
  header = open(sys.argv[1]).read()
  source = open("src/x2cui.x").read()
  begin = source.index(BEGIN % "methods")
  end = source.index(END % "methods")
  hand = source[:begin] + source[end:]
  existing = set(re.findall(r"^\$cui\.method\((cui_\w+)\);", hand, flags=re.M))
  for method in re.findall(r"\bUi\.(\w+)\(", hand):
    existing |= {"cui_" + method, "cui_" + method + "_ex"}
  methods, macros = forms(header, existing)
  replace("src/x2cui.x", "methods", methods)
  replace("src/x2cui-arrays.x", "macros", macros)
  print(f"{len(methods)} methods, {len(macros)} macros")


if __name__ == "__main__":
  main()
