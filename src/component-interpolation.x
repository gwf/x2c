/*  component-interpolation.x -- interpolated Strings

    A `%"..."` literal reaches its rule as the `segments` form, each part
    already a `String`: cached text, a converted `$` insertion, or raw text
    that constructed syntax spells. The rule joins the parts with
    `String_join` over a `List` chain of them, which the compiler boxes and
    evaluates once each, left to right. The join is C text the emitter
    places as written around the chain, so a unit gains no declaration of
    `String_join` and the formatter keeps its line breaks.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"

/* Raw text as the String its C literal spells. */
meta static Code _interpolation_raw(String raw) {
  Code literal = %(expr (* char) (literal (* char) ${raw.repr()}));
  return $!String{ String.new($literal) };
}

$rewrite(%(expr ("String") (segments *)))
/** Joins an interpolated String's parts. */
meta Code interpolation(Code code) {
  match (code) case %(expr ? (segments *segments)): {
    Array parts = [];
    foreach (List segment, segments) match (segment) {
      case %((!or segexp segvar) ?value): parts.push(value);
      case %(segraw ?text): parts.push(_interpolation_raw(text));
      default: parts.push(%(expr ("String") $segment));
    }
    Var chain = %(nil);
    while (parts.len())
      chain = %(expr ("List") (cons ${parts.take_last()} $chain));
    return Code.lowered(%(expr ("String") ("String_join(NULL, " $chain ")")));
  }
  return code;
}
