#pragma once

/* meta-type-parameter-defs.x -- a meta function with a `Type` parameter. */

/* One line per part, so no part wraps. Methods, which String has many of,
   print as whether `len` is one. */
meta List describe(TypeInfo type) {
  Array parts = [];
  foreach (List part, type) {
    List methods = part.cadr();
    parts.push(part.car() == <methods>
                 ? %"(methods len ${methods.contains("len")})"
                 : part.repr());
  }
  return x2c_literal_string(String.join("\n  ", parts));
}

macro Expression $type.describe(Expr $value) => $describe($value);
