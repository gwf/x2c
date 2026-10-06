#pragma once

/*  dataset-output.x -- graph TSV headers and row layouts */

macro Expression $output.graph.function_header() => "".join(
  %("function_id\tkind\tsubtree\tunit\tunit_lines\tsource_order\t"
    "source_name\temitted_name\tvisibility\texternal_calls\t"
    "indirect_calls"));

macro Stmt $output.graph.function_row(
  Expr $rows, Expr $id, Expr $kind, Expr $subtree, Expr $unit,
  Expr $lines, Expr $order,
  Expr $source, Expr $emitted, Expr $visibility, Expr $external,
  Expr $indirect) {
  String row = "%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s\t%s\t%d\t%d".printf(
    $id, $kind, $subtree, $unit, $lines, $order, $source, $emitted,
    $visibility, $external, $indirect);
  $rows.push(row);
}

macro Expression $output.graph.call_header() =>
  "caller_id\tcallee_id\tstatic_calls";

macro Expression $output.graph.call_row(
  Expr $caller, Expr $callee, Expr $count) =>
  "%s\t%s\t%d".printf($caller, $callee, $count);
