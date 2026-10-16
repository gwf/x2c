#include <stdio.h>
#include "meta.x"

/* A case on a visible macro tests its derived pattern in place, through
   the case's view, and matches what the generic case through a Macro
   variable matches, with the same captures. */
macro Stmt $raised2(Expr $code, Expr @details) { raise %($code @details); }
macro Expression $indexed2(Expr $receiver, Expr $selector) =>
  $receiver[$selector];

static String inline_raise(List node) {
  match (node) case $raised2(?code, *details):
    return %"${code.repr()} ${details.var().repr()}";
  return "none";
}

static String generic_raise(List node) {
  Macro raised = $raised2;
  match (node) case raised(?code, *details):
    return %"${code.repr()} ${details.var().repr()}";
  return "none";
}

static String inline_index(List node) {
  match (node) case $indexed2(?receiver, ?selector):
    return %"${receiver.repr()} ${selector.repr()}";
  return "none";
}

static String generic_index(List node) {
  Macro indexed = $indexed2;
  match (node) case indexed(?receiver, ?selector):
    return %"${receiver.repr()} ${selector.repr()}";
  return "none";
}

int main(void) {
  Macro raised = $raised2;
  List statements = %(
    (raise E (args K V)) (seq (raise E (args K V))) (seq (raise E) extra)
    (at P (raise E (args K V))) (raise (at P E) (args))
    (raise E (at P (args K))) (raise E (args K) extra) (stmnt E));
  foreach (List node, statements)
    printf("%s | %s\n", inline_raise(node), generic_raise(node));
  List pending = raised(%(expr ("int") (literal (int) "1")), %());
  printf("%s | %s\n", inline_raise(pending), generic_raise(pending));
  List expressions = %(
    (expr T (index R S)) (expr T (at P (index R S)))
    (at P (expr T (index R S))) (index R S) (expr T (index R)));
  foreach (List node, expressions)
    printf("%s | %s\n", inline_index(node), generic_index(node));
  return 0;
}
