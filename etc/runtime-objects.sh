#!/bin/sh
# runtime-objects.sh -- the runtime objects the compiler links whole
#
# Usage: runtime-objects.sh <compiler object>... -- <runtime object>...
#
# Prints, one per line and in argument order, the runtime objects the
# compiler links whole, so that a native module can call their functions.
# The objects the compiler's own code reaches are linked from the archive
# regardless and are not printed. Of the rest, an object is left out when it
# calls a function that reserves a Var class row, or needs a function that
# only a left-out object defines: linking it could spend rows of the 32-row
# budget at startup.
set -eu

{
  role=compiler
  for object in "$@"; do
    if [ "$object" = -- ]; then
      role=runtime
      continue
    fi
    "${NM:-nm}" -P -g "$object" | sed "s|^|$role $object |"
  done
} | awk '
BEGIN {
  split("x2c_try_register_descriptor x2c_register_descriptor " \
        "x2c_register_type Var_register_object_tag " \
        "x2c_register_tagged_descriptor x2c_try_register_tagged_descriptor",
        names, " ")
  for (i in names) {
    reserves[names[i]] = 1
    reserves["_" names[i]] = 1
  }
}
{
  role = $1; object = $2; name = $3; type = $4
  if (!(object in seen)) {
    seen[object] = 1
    if (role == "runtime") order[++count] = object
    else linked[object] = 1
  }
  if (type == "U") {
    uses[object] = uses[object] " " name
    if (name in reserves) reserving[object] = 1
  }
  else if (role == "runtime") definers[name] = definers[name] " " object
}
END {
  # The archive members the compiler links today.
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
