/*  answer.x -- a meta function and macro for imported-macros.x */

#pragma once

meta int example_answer_offset(void) => 2;

macro Expression $example.answer(Expr $base) =>
  $base + $example_answer_offset();
