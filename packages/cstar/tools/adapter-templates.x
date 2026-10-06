#pragma once

/* C* builder spellings. The adapter selects and orders these constructions. */

macro Expression $source.cstar.pointer_type(Expr $base) =>
  %"make_pointer_type(${$base})";

macro Expression $source.cstar.function_type(Expr $result, Expr $types) =>
  %"make_function_type(${$result}, (ctype []) " +
  %"{ ${$types.join(", ")} }, ${$types.len()})";

macro Expression $source.cstar.call(
  Expr $name, Expr $signature, Expr $arguments, Expr $count, Expr $result) =>
  %"make_call_expr(make_var_expr(\"${$name}\", ${$signature}), " +
  %"${$arguments}, ${$count}, ${$result})";

macro Expression $source.cstar.constant(Expr $spelling, Expr $type) =>
  %"make_const_expr(${$spelling}, ${$type})";

macro Expression $source.cstar.variable(Expr $name, Expr $type) =>
  %"make_var_expr(\"${$name}\", ${$type})";

macro Expression $source.cstar.index(
  Expr $base, Expr $offset, Expr $type) =>
  %"make_index_expr(${$base}, ${$offset}, ${$type})";

macro Expression $source.cstar.cast(Expr $value, Expr $type) =>
  %"make_cast_expr(${$value}, ${$type})";

macro Expression $source.cstar.binary(
  Expr $operator, Expr $left, Expr $right, Expr $type) =>
  %"make_binary_expr(${$operator}, ${$left}, " +
  %"${$right}, ${$type})";

macro Expression $source.cstar.dereference(Expr $value, Expr $type) =>
  %"make_deref_expr(${$value}, ${$type})";

macro Expression $source.cstar.address(Expr $value, Expr $type) =>
  %"make_addrof_expr(${$value}, ${$type})";

macro Expression $source.cstar.unary(
  Expr $operator, Expr $value, Expr $type) =>
  %"make_unary_expr(${$operator}, ${$value}, ${$type})";

macro Expression $source.cstar.assertion(Expr $text) =>
  %"make_cst_assert(cstar.program_assertion(\"${$text}\"), 0)";

macro Expression $source.cstar.invariant(Expr $text) =>
  %"make_cst_invariant(cstar.program_assertion(\"${$text}\"), 0)";

macro Expression $source.cstar.separation_invariant(Expr $text) =>
  %"make_cst_invariant(cstar.assertion(\"${$text}\"), 1)";

macro Expression $source.cstar.increment(
  Expr $value, Expr $step, Expr $position) =>
  %"make_inc_dec(${$value}, INCDEC_${$step}_${$position})";

macro Expression $source.cstar.block_begin() => "make_block_begin()";

macro Expression $source.cstar.block_end() => "make_block_end()";

macro Expression $source.cstar.declaration_value(
  Expr $name, Expr $type, Expr $value) =>
  %"make_var_def_init(\"${$name}\", " + %"${$type}, ${$value})";

macro Expression $source.cstar.declaration(Expr $name, Expr $type) =>
  %"make_var_def(\"${$name}\", ${$type})";

macro Expression $source.cstar.return_empty() => "make_return()";

macro Expression $source.cstar.return_value(Expr $value) =>
  %"make_return_expr(${$value})";

macro Expression $source.cstar.condition(Expr $value) =>
  %"make_if_condition(${$value})";

macro Expression $source.cstar.alternative() => "make_else()";

macro Expression $source.cstar.loop_condition(Expr $value) =>
  %"make_while_condition(${$value})";

macro Expression $source.cstar.assignment(Expr $left, Expr $right) =>
  %"make_assign(${$left}, ${$right}, ASSIGNOP_ASSIGN)";

macro Expression $source.cstar.compute(Expr $value) =>
  %"make_compute(${$value})";

macro Expression $source.cstar.function_start(
  Expr $name, Expr $result, Expr $types, Expr $names, Expr $count) =>
  %"make_function_start(\"${$name}\", ${$result}, " +
  %"${$types}, ${$names}, ${$count})";

macro Expression $source.cstar.ghost_parameters(Expr $count) =>
  %"make_cst_param((type *) NULL, 0, ghosts, ${$count})";

macro Expression $source.cstar.precondition(Expr $text) =>
  %"make_cst_require(cstar.assertion(\"${$text}\"))";

macro Expression $source.cstar.postcondition(Expr $text) =>
  %"make_cst_ensure(cstar.assertion(\"${$text}\"))";

macro Expression $source.cstar.function_end() => "make_function_end()";
