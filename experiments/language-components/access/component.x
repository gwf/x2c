/* Indexed source operations reuse the runtime's storage and update rules. */
#pragma once
#include "rewrite.x"

macro Expression $at(Expr $base, Expr $key) => $base[$key];
macro Expression $put(Expr $base, Expr $key, Expr $value) =>
  $base[$key] = $value;
macro Expression $add_at(Expr $base, Expr $key, Expr $value) =>
  $base[$key] += $value;
macro Expression $before_at(Expr $base, Expr $key) => ++$base[$key];
macro Expression $after_at(Expr $base, Expr $key) => $base[$key]++;

$rewrite($at, $!Array{${%(!and ?base)}}, <?key>)
$rewrite($at, $!Map{${%(!and ?base)}}, <?key>)
meta Code read_collection(Code code) {
  match (code) case $at(?base, ?key):
    return $!Var{ $base.getindex($key) };
  return code;
}

$rewrite($put, $!Array{${%(!and ?base)}}, <?key>, <?value>)
$rewrite($put, $!Map{${%(!and ?base)}}, <?key>, <?value>)
meta Code store_collection(Code code) {
  match (code) case $put(?base, ?key, ?value):
    return $!Var{ $base.setindex($key, $value) };
  return code;
}

$rewrite($add_at, $!Array{${%(!and ?base)}}, <?key>, <?value>)
$rewrite($add_at, $!Map{${%(!and ?base)}}, <?key>, <?value>)
meta Code update_collection(Code code) {
  match (code) case $add_at(?base, ?key, ?value):
    return $!Var{ $base.updateindex($key, <+>, $value) };
  return code;
}

$rewrite($before_at, $!Array{${%(!and ?base)}}, <?key>)
$rewrite($before_at, $!Map{${%(!and ?base)}}, <?key>)
meta Code prefix_collection(Code code) {
  match (code) case $before_at(?base, ?key):
    return $!Var{ $base.updateindex($key, <+>, 1) };
  return code;
}

$rewrite($after_at, $!Array{${%(!and ?base)}}, <?key>)
$rewrite($after_at, $!Map{${%(!and ?base)}}, <?key>)
meta Code postfix_collection(Code code) {
  match (code) case $after_at(?base, ?key):
    return $!Var{ $base.postfixindex($key, <++>) };
  return code;
}
