/*  component-literals.x -- Array and Map literals

    A collection literal builds its container with the counted constructor,
    which receives each element converted to `Var`, in source order; an
    empty brace among the elements is an empty Map. The compiler keeps the
    elements in source order: see "literal order" in `src/transform.x`.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"

/** Builds an Array literal from its elements. */
$rewrite($array_value)
meta Code array_literal(Code code) {
  match (code) case $array_value(*items): {
    if (!items) return $!Array{ Array.new() };
    Array values = [];
    foreach (Code item, items) {
      if (item.match(%(expr ? (composite (commas)))))
        item = $!Map{ Map.new() };
      values.push(%(expr ("Var") (var $item)));
    }
    int count = values.len();
    List elements = values.list_free();
    return $!Array{ Array.update_n(Array.new(), $count, @elements) };
  }
  return code;
}

/** Builds a Map literal from its keys and values, alternating. */
$rewrite($map_value)
meta Code map_literal(Code code) {
  match (code) case $map_value(*rows): {
    if (!rows) return $!Map{ Map.new() };
    Array values = [];
    foreach (List row, rows)
      foreach (Code item, row.cdr()) {
        if (item.match(%(expr ? (composite (commas)))))
          item = $!Map{ Map.new() };
        values.push(%(expr ("Var") (var $item)));
      }
    int count = rows.len();
    List elements = values.list_free();
    return $!Map{ Map.update_n(Map.new(), $count, @elements) };
  }
  return code;
}
