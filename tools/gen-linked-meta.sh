#!/bin/sh
# Writes src/linked-meta.x, the shipped `meta` code compiled into the
# compiler, from the sources that define it. Bodied functions and initialized
# static `meta` values from ordinary shipped sources are copied without
# their `meta` markers, so their tokens, and
# therefore their definition hashes, match the source. A public function
# with a run-time form is bound to its ordinary provider's definition: one that
# is not static and reaches no compiler operation. The file is rewritten
# only when its text changes.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$root/src/linked-meta.x}
cd "$root"

# Native advertisements already bind their runtime symbols. Bodied meta
# definitions are discovered in the ordinary source modules that own them.
sources=$(awk '/^meta / && !/^meta native / && !seen[FILENAME]++ {
    print FILENAME
  }' lib/*.x src/*.x src/components/*.x |
  sed '/^src\/linked-meta\.x$/d' | sort)

tmp="$out.$$"
trap 'rm -f "$tmp"' EXIT
awk '
function scan(line,    i, ch, n) {
  n = length(line)
  for (i = 1; i <= n; i++) {
    ch = substr(line, i, 1)
    if (incomment) {
      if (ch == "*" && substr(line, i + 1, 1) == "/") { incomment = 0; i++ }
      continue
    }
    if (quote != "") {
      if (ch == "\\") i++
      else if (ch == quote) quote = ""
      continue
    }
    if (ch == "/" && substr(line, i + 1, 1) == "*") { incomment = 1; i++ }
    else if (ch == "/" && substr(line, i + 1, 1) == "/") break
    else if (ch == "\"" || ch == "\x27") quote = ch
    else if (ch == "(" || ch == "{" || ch == "[") depth++
    else if (ch == ")" || ch == "}" || ch == "]") depth--
  }
}
function finish(    name, text) {
  text = def
  if (!isvalue) {
    if (text !~ /=>/ && text !~ /\{/) { prototypes[++nproto] = defname; return }
    if (text !~ /\)[ \t\n]*(=>|\{)/) return
  }
  ndef++
  names[ndef] = defname
  bodies[ndef] = (defdoc == "" ? "" : defdoc "\n") text
  statics[ndef] = (header ~ /^meta static /)
  values[ndef] = isvalue
  files[ndef] = FILENAME
}
FNR == 1 { capturing = 0; indoc = 0; doc = "" }
capturing {
  def = def "\n" $0
  scan($0)
  if (depth == 0 && $0 ~ /[;}][ \t]*$/) { capturing = 0; finish() }
  next
}
# A doc comment directly above a definition travels with its copy.
indoc { doc = doc "\n" $0; if ($0 ~ /\*\//) indoc = 0; next }
/^\/\*\*/ { doc = $0; if ($0 !~ /\*\//) indoc = 1; next }
/^meta / && !/^meta native / {
  header = $0
  defdoc = doc
  isvalue = ($0 ~ /^meta static / && $0 ~ /^[^(=]*=/)
  defname = $0
  if (isvalue) sub(/[ \t]*=.*/, "", defname)
  sub(/\(.*/, "", defname)
  sub(/.*[^A-Za-z0-9_]/, "", defname)
  def = substr($0, 6)
  depth = 0; quote = ""; incomment = 0
  scan($0)
  if (depth == 0 && $0 ~ /[;}][ \t]*$/) finish()
  else capturing = 1
}
{ doc = "" }
function refers(text, name, value) {
  return text ~ ("(^|[^A-Za-z0-9_])" name \
    (value ? "([^A-Za-z0-9_]|$)" : "[ \t]*\\("))
}
function push(mode, depth) { modes[++sp] = mode; depths[sp] = depth }
# The text a definition evaluates: comments, strings, and the data in its
# `%(...)` lists and `$!` quotations become spaces, except the code of a
# `${...}` or `@{...}` hole and the name a `$name` or `@name` hole inserts.
# A quotation keeps a `(` right after a hole, where a slot calls a
# definition.
function code_of(text,    out, i, j, n, ch, two, mode, hole) {
  n = length(text); out = ""; sp = 0; push("c", 0)
  for (i = 1; i <= n; i++) {
    ch = substr(text, i, 1); two = substr(text, i, 2); mode = modes[sp]
    if (mode == "s") {
      if (ch == "\\") i++
      else if (ch == "\"") sp--
      else if (two == "${") { push("c", 1); i++ }
      out = out " "; continue
    }
    if (two == "/*") {
      j = index(substr(text, i + 2), "*/"); i = j ? i + j + 2 : n
      out = out " "; continue
    }
    if (two == "//") {
      j = index(substr(text, i), "\n"); i = j ? i + j - 2 : n
      out = out " "; continue
    }
    if (two == "%\"") { push("s", 0); i++; out = out " "; continue }
    if (ch == "\"" || ch == "\x27") {
      for (j = i + 1; j <= n && substr(text, j, 1) != ch; j++)
        if (substr(text, j, 1) == "\\") j++
      i = j; out = out " "; continue
    }
    if (mode != "c" && (two == "${" || two == "@{")) {
      push("c", 1); i++; out = out " "; continue
    }
    if (mode != "c" && (ch == "$" || ch == "@") &&
        match(substr(text, i + 1), /^[A-Za-z_][A-Za-z0-9_]*/)) {
      out = out "$" substr(text, i + 1, RLENGTH); i += RLENGTH
      hole = mode == "q"; continue
    }
    if (mode == "c" && (two == "%(" || two == "$!")) {
      push(two == "%(" ? "l" : "q", two == "%("); i++; out = out " "; continue
    }
    if (ch == "(" || ch == "{" || ch == "[") depths[sp]++
    # `$!(T){ ... }` quotes its type and then its code.
    else if ((ch == ")" || ch == "}" || ch == "]") && --depths[sp] == 0 &&
             sp > 1 && !(mode == "q" && ch == ")" &&
                         substr(text, i + 1) ~ /^[ \t\n]*\{/)) {
      sp--; out = out " "; continue
    }
    if (mode == "c" || (hole && ch == "(")) out = out ch
    else out = out " "
    hole = 0
  }
  return out
}
END {
  # A static definition has no run-time symbol, so it is copied. One that
  # reaches a compiler operation, through what it calls, has no run-time
  # form, so it is copied too; any other public function has one.
  for (i = 1; i <= ndef; i++) {
    code[i] = code_of(bodies[i])
    reaches[i] = values[i]
    for (p = 1; p <= nproto; p++)
      if (refers(code[i], prototypes[p])) reaches[i] = 1
  }
  do {
    changed = 0
    for (i = 1; i <= ndef; i++) {
      if (reaches[i]) continue
      for (j = 1; j <= ndef; j++)
        if (reaches[j] && refers(code[i], names[j], values[j])) {
          reaches[i] = 1; changed = 1; break
        }
    }
  } while (changed)
  for (i = 1; i <= ndef; i++) copied[i] = statics[i] || reaches[i]

  print "/*  linked-meta.x -- shipped `meta` code compiled into the compiler"
  print ""
  print "    Generated by tools/gen-linked-meta.sh; do not edit. Bodied `meta`"
  print "    functions and initialized static values from shipped source"
  print "    modules appear without their `meta` markers,"
  print "    so their functions and initializers execute as native code."
  print "    `Compiler.bind_linked_meta` binds an included definition to its"
  print "    copy when its definition hashes agree, and a prelude component\047s"
  print "    definition always. Public"
  print "    functions with a run-time form bind to their ordinary provider\047s"
  print "    definitions and have no copy here."
  print "*/"
  print ""
  print "#pragma once"
  print ""
  print "#include \"x2c.x\""
  # Components are already supplied by the compiler prelude.
  for (i = 1; i <= ndef; i++)
    if (files[i] !~ /^src\/components\// && !included[files[i]]++) {
      unit = files[i]; sub(/.*\//, "", unit)
      print "#include \"" unit "\""
    }
  last = ""
  for (i = 1; i <= ndef; i++) {
    if (!copied[i]) continue
    if (files[i] != last) {
      print ""
      print "/* --- " files[i] " " substr("--------------------------------------------------------------------------", 1, 68 - length(files[i])) " */"
      last = files[i]
    }
    print ""
    print bodies[i]
  }
  print ""
  print "/* --- the linked inventory " substr("--------------------------------------------------", 1, 48) " */"
  print ""
  print "macro Stmt $linked.row(Expr $rows, Expr $name, Expr $function) {"
  print "  $rows[$name] = Func.new("
  print "    $function, $(_x2c.literal.list (_x2c.function.native-type $function)));"
  print "}"
  print ""
  print "/** Returns the linked copies, and the runtime builders, by name. */"
  print "Map linked_meta_targets(void) {"
  print "  Map rows = {};"
  for (i = 1; i <= ndef; i++)
    if (copied[i] && !values[i])
      print "  $linked.row(rows, \"" names[i] "\", " names[i] ");"
  for (i = 1; i <= ndef; i++)
    if (!copied[i]) print "  $linked.row(rows, \"" names[i] "\", " names[i] ");"
  print "  return rows;"
  print "}"
  print ""
  print "macro Expression $linked.hashes() => $(_x2c.meta.linked.hashes);"
  print ""
  print "/** Returns linked definition hashes and provider source dependencies. */"
  print "Map linked_meta_hashes(void) {"
  print "  return $linked.hashes();"
  print "}"
}
' $sources > "$tmp"
if [ -e "$out" ] && cmp -s "$tmp" "$out"; then
  rm -f "$tmp"
else
  mv "$tmp" "$out"
fi
trap - EXIT
