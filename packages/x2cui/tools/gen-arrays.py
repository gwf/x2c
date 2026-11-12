#!/usr/bin/env python3
"""Writes the x2c forms of the CUI functions that take arrays.

    python3 tools/gen-arrays.py deps/include/cui/cui.h

A function in cui.h whose first parameter is `cui_ctx *` and which has no
row in the `expand` table and no hand-written method in src/x2cui.x takes
an array of records, numbers, or flags. This tool writes one `Ui` method for each,
between markers in src/x2cui.x. The method takes each array as a pointer
and its count, as CUI declares them; a call site passes a C array and
`$x2cui.count(array)`. It keeps CUI's parameter names. Rerun it after
changing the pinned CUI version and review the difference. Variadic
functions get no form.

It also writes the table of the methods in src/x2cui.x, generated here or
written by hand, that may have a method form, and the table in
src/x2cui-options.x of the parameters that name an icon. A row names a method and
the positions of its arrays whose count follows them, so the form
supplies each count: `ui.tab_bar("tabs", tabs, selected, variant: pill)`.
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
# Arrays whose count is another parameter's: no count of their own. The
# filter bar reads one mask for each field.
SHARED = {("cui_toggle_group_ex", "values"),
          ("cui_multi_select_ex", "selected"),
          ("cui_blame_ex", "line_commit"), ("cui_heatmap_ex", "values"),
          ("cui_filter_bar", "selected")}


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
  """Returns the x2c parameters and the C arguments of a method, and the
  positions among its parameters of the arrays whose count follows."""
  declared, passed, pairs = [], [], []
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
      index += 1
      while rest[index][1] != counter:
        declared.append(f"{rest[index][0]} {rest[index][1]}")
        passed.append(rest[index][1])
        index += 1
      declared.append(f"{rest[index][0]} {rest[index][1]}")
      passed.append(rest[index][1])
      index += 1
      continue
    elif ("*" in ctype and after[0] == "int *" and after2[0] == "int"
          and after2[1] == "capacity"):
      # An array the user grows: its live count, then its capacity.
      pairs.append(len(declared))
      declared += [f"{ctype}{pname}", f"int &{after[1]}", "int capacity"]
      passed += [pname, f"&{after[1]}", "capacity"]
      index += 3
      continue
    elif "*" in ctype and after[0] in ("int", "size_t"):
      pairs.append(len(declared))
      declared += [f"{ctype}{pname}", f"{after[0]} {after[1]}"]
      passed += [pname, after[1]]
      index += 2
      continue
    elif "*" in ctype and not ctype.startswith("const "):
      declared.append(f"{ctype[:-1].strip()} &{pname}")
      passed.append(f"&{pname}")
    else:
      declared.append(f"{ctype} {pname}".replace("* ", "*"))
      passed.append(pname)
    index += consumed
  return declared, passed, pairs


def forms(header, existing):
  methods, rows = [], []
  for result, name, params in prototypes(header):
    if not params[0].startswith("cui_ctx *") or name in existing:
      continue
    if name in SKIP or "..." in params or any("va_list" in p for p in params):
      continue
    short = name[4:-3] if name.endswith("_ex") else name[4:]
    declared, passed, pairs = classify(name, params)
    rows.append(f"({short} {' '.join(map(str, pairs))})" if pairs else short)
    if result == "const char *":
      result = "String"
    methods.append(
      f"/** Calls `{name}`. */\n"
      + wrap(f"inline {result} Ui.{short}(", ["Ui ui"] + declared, ") =>")
      + "\n" + wrap(f"  {name}(", ["ui"] + passed, ");", "    ") + "\n")
  return methods, rows


def written_methods(source):
  """Rows for the methods written by hand in `source`, except those that
  take a sequence of values: a name, or a name and the positions of the
  pointers that an `int` count follows."""
  pattern = r"^(?:inline )?[\w ]+ Ui\.(\w+)\(([^()]*)\)\s*(?:=>|\{)"
  rows = []
  for match in re.finditer(pattern, source, flags=re.M):
    if "@" in match.group(2):
      continue
    params = [" ".join(p.split()) for p in match.group(2).split(",")][1:]
    pairs = [i for i in range(len(params) - 1)
             if "*" in params[i] and params[i + 1].startswith("int ")]
    name = match.group(1)
    rows.append(f"({name} {' '.join(map(str, pairs))})" if pairs else name)
  return rows


def is_icon(name):
  """Whether a parameter or field named `name` holds an icon."""
  return name == "icon" or name.startswith("icon_") or name.endswith("_icon")


def icon_parameters(header, hand):
  """Rows `("method" position)` for the parameters that name an icon,
  counted after the receiver among a method's x2c parameters."""
  rows = []
  for result, name, params in prototypes(header):
    if not params[0].startswith("cui_ctx *"):
      continue
    if name in SKIP or "..." in params or any("va_list" in p for p in params):
      continue
    short = name[4:-3] if name.endswith("_ex") else name[4:]
    if not any(is_icon(p.split("*")[-1].strip()) for p in params):
      continue
    declared = classify(name, params)[0]
    for position, param in enumerate(declared):
      if param.startswith("String ") and is_icon(param.split()[-1]):
        rows.append(f'("{short}" {position})')
  pattern = r"^(?:inline )?[\w ]+ Ui\.(\w+)\(([^()]*)\)\s*(?:=>|\{)"
  for match in re.finditer(pattern, hand, flags=re.M):
    params = [" ".join(p.split()) for p in match.group(2).split(",")][1:]
    for position, param in enumerate(params):
      if param.startswith("String ") and is_icon(param.split()[-1]):
        rows.append(f'("{match.group(1)}" {position})')
  return list(dict.fromkeys(rows))


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
  table = re.search(r"^expand %\((.*?)\)$", hand, flags=re.M | re.S).group(1)
  existing = set(table.split())
  for method in re.findall(r"\bUi\.(\w+)\(", hand):
    existing |= {"cui_" + method, "cui_" + method + "_ex"}
  methods, rows = forms(header, existing)
  replace("src/x2cui.x", "methods", methods)
  names = written_methods(hand) + rows
  table = wrap("expand %(", names, ")", "  ").replace(", ", " ").replace(",\n", "\n")
  replace("src/x2cui.x", "forms",
          [table + "\nmacro Unit(Name $method, Literal @pairs) {\n"
           "  @x2cui_form($method, $pairs)\n}"])
  icons = icon_parameters(header, hand)
  replace("src/x2cui-options.x", "icons",
          [wrap("meta static List _icon_parameters = %(", icons, ");", "  ")
           .replace(", ", " ").replace(",\n", "\n")])
  print(f"{len(methods)} methods, {len(names)} rows, {len(icons)} icons")


if __name__ == "__main__":
  main()
