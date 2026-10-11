#pragma once
#include "rewrite.x"

macro Stmt $counted_switch(Expr $subject, Stmt $body) {
  switch ($subject) $body
}

$rewrite($counted_switch)
/* Each switch on an int is counted, then switches as written. The new
   switch in the replacement lowers once; a switch nested in the body
   reaches the rule again. */
meta Code count_switch(Code node) {
  match (node) case %(switch (!set ?subject (expr (int) ?)) ?body):
    return $!{ { counted++; switch ($subject) $body } };
  return node;
}
