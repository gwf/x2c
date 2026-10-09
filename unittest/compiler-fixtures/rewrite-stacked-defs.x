/* Every decorator in a stack must survive interface collection and replay. */
#pragma once
#include "rewrite.x"

typedef struct Stacked { int value; } Stacked;
macro Expression $stacked_add(Expr $left, Expr $right) => $left + $right;
macro Expression $stacked_sub(Expr $left, Expr $right) => $left - $right;
macro Expression $stacked_mul(Expr $left, Expr $right) => $left * $right;

$rewrite($stacked_add)
$rewrite($stacked_sub)
$rewrite($stacked_mul)
meta Code stacked_operation(Code code) {
  match (code) {
    case $stacked_add(?left, ?right): return $!int{11};
    case $stacked_sub(?left, ?right): return $!int{22};
    case $stacked_mul(?left, ?right): return $!int{33};
  }
  return code;
}
