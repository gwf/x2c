#pragma once
#include "x2c.x"
#include "meta.x"

macro Stmt $announcement(Expr $message) { puts($message); }
meta Code trace_statements(List statements) {
  match (statements) case %(?head *tail): {
    Code rest = trace_statements(tail);
    match (head) case $announcement(?message):
      return $!{ puts("before"); puts($message); $rest };
    return $!{ $head $rest };
  }
  return $!{};
}
macro Stmt $trace(Stmt @items) { @trace_statements($items) }
