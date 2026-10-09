/* Included components use source patterns, quotations, and Code methods. */
#pragma once
#include "rewrite.x"

typedef struct Distance { int value; } Distance;
typedef struct Choice { int value; } Choice;

macro Expression $addition(Expr $left, Expr $right) => $left + $right;
macro Stmt $selection(Expr $subject, Stmt $body) { switch ($subject) $body }

meta static int addition_candidates = 0;
meta int candidate_count(void) => addition_candidates;

$rewrite($addition,
  $!Distance{${%(!and ?left)}}, $!Distance{${%(!and ?right)}})
meta Code add_distances(Code code) {
  addition_candidates++;
  match (code) case $addition(?left, ?right): {
    Code lhs = left, rhs = right;
    return $!Distance{ (Distance) { .value = $lhs.value + $rhs.value } };
  }
  x2c_diagnostic_fail("binary classifier dispatched an unrelated operation", NULL);
}

$rewrite($selection, $!Choice{${%(!and ?subject)}}, <?body>)
meta Code select_choice(Code code) {
  match (code) case $selection(?subject, ?body): {
    Code value = subject;
    return $!{ switch ($value.value) $body };
  }
  x2c_diagnostic_fail("statement classifier dispatched an unrelated node", NULL);
}
