#!/bin/sh
# runtime-objects.sh -- the runtime objects the compiler links whole
#
# Usage: runtime-objects.sh <compiler object>... -- <runtime object>...
#
# Prints, one per line and in argument order, the runtime objects the
# compiler links whole, so that a native module can call their functions.
# The runtime objects the compiler's own code reaches are linked from the
# archive regardless and are not printed. A class that boxes as a Var
# reserves one of the 32 Var class rows in its object's file initializer,
# through x2c_register_descriptor or x2c_register_tagged_descriptor. Of the
# other runtime objects, one that makes such a call is left out, and so is
# one that needs a function only a left-out object defines, so linking the
# rest reserves no row the compiler did not already reserve. Exits nonzero
# when nm fails; NM names another nm. Object paths must not contain spaces.
set -eu

compiler=
for object in "$@"; do
  shift
  [ "$object" = -- ] && break
  compiler="$compiler $object"
done
symbols=$("${NM:-nm}" -A -P -g $compiler "$@")
printf '%s\n' "$symbols" | awk -v compiler="$compiler" '
BEGIN {
  n = split(compiler, list, " ")
  for (i = 1; i <= n; i++) linked[list[i]] = 1
}
{
  object = $1; sub(/:$/, "", object)
  name = $2; type = $3
  if (!(object in seen)) {
    seen[object] = 1
    if (!(object in linked)) order[++count] = object
  }
  if (type == "U") {
    uses[object] = uses[object] " " name
    if (name ~ /^_?x2c_register_(tagged_)?descriptor$/) reserving[object] = 1
  }
  else if (!(object in linked)) definers[name] = definers[name] " " object
}
END {
  # The runtime objects the compiler links from the archive today.
  do {
    changed = 0
    for (object in linked) {
      n = split(uses[object], used, " ")
      for (j = 1; j <= n; j++) {
        m = split(definers[used[j]], owners, " ")
        for (k = 1; k <= m; k++)
          if (!(owners[k] in linked)) {
            linked[owners[k]] = 1
            changed = 1
          }
      }
    }
  } while (changed)
  for (i = 1; i <= count; i++)
    if (!(order[i] in linked) && order[i] in reserving) out[order[i]] = 1
  do {
    changed = 0
    for (i = 1; i <= count; i++) {
      object = order[i]
      if (object in linked || object in out) continue
      n = split(uses[object], used, " ")
      for (j = 1; j <= n; j++) {
        if (!(used[j] in definers)) continue
        m = split(definers[used[j]], owners, " ")
        available = 0
        for (k = 1; k <= m; k++) if (!(owners[k] in out)) available = 1
        if (!available) {
          out[object] = 1
          changed = 1
          break
        }
      }
    }
  } while (changed)
  for (i = 1; i <= count; i++)
    if (!(order[i] in linked) && !(order[i] in out)) print order[i]
}'
