/*  component-interpolation.x -- interpolated Strings

    A `%"..."` literal reaches its rule as the `segments` form, each part
    already a `String`: cached text, a converted `$` insertion, or raw text
    that constructed syntax spells. The rule joins the parts with
    `String.join` over a `List` chain of them, which the compiler boxes and
    evaluates once each, left to right.
*/
#pragma once
#include "rewrite.x"

$rewrite(%(expr ("String") (segments *)))
/** Joins an interpolated String's parts. */
meta Code interpolation(Code code) {
  match (code) case %(expr ? (segments *segments)): {
    Array parts = [];
    foreach (List segment, segments) match (segment) {
      case %((!or segexp segvar) ?value): parts.push(value);
      case %(segraw ?text):
        parts.push(%(expr ("String") (literal ("String") $text)));
      default: parts.push(%(expr ("String") $segment));
    }
    Var chain = %(nil);
    while (parts.len())
      chain = %(expr ("List") (cons ${parts.take_last()} $chain));
    return $!String{ String.join(NULL, $chain) };
  }
  return code;
}
