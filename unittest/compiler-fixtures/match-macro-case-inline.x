#include <stdio.h>
#include "meta.x"

/* A case on a visible macro tests its derived pattern in place, through
   the case's view, and matches what the generic case through a Macro
   variable matches, with the same captures. Subjects that are their own
   view start the tests or miss without the runtime; wrapped ones, a
   retained invocation, and a template shell still reach it. */
macro Stmt $raised2(Expr $code, Expr @details) { raise %($code @details); }
macro Expression $indexed2(Expr $receiver, Expr $selector) =>
  $receiver[$selector];
macro Stmt $returned2() { return; }
macro Stmt $tried2(Stmt $body, Stmt $finalizer) {
  try $body finally $finalizer
}

static String inline_raise(List node) {
  match (node) case $raised2(?code, *details):
    return %"$(code.repr()) $(details.var().repr())";
  return "none";
}

static String generic_raise(List node) {
  Macro raised = $raised2;
  match (node) case raised(?code, *details):
    return %"$(code.repr()) $(details.var().repr())";
  return "none";
}

static String inline_index(List node) {
  match (node) case $indexed2(?receiver, ?selector):
    return %"$(receiver.repr()) $(selector.repr())";
  return "none";
}

static String generic_index(List node) {
  Macro indexed = $indexed2;
  match (node) case indexed(?receiver, ?selector):
    return %"$(receiver.repr()) $(selector.repr())";
  return "none";
}

static String inline_return(List node) {
  match (node) case $returned2(): return "return";
  return "none";
}

static String generic_return(List node) {
  Macro returned = $returned2;
  match (node) case returned(): return "return";
  return "none";
}

static String inline_try(List node) {
  match (node) case $tried2(?body, ?finalizer):
    return %"$(body.repr()) $(finalizer.repr())";
  return "none";
}

static String generic_try(List node) {
  Macro tried = $tried2;
  match (node) case tried(?body, ?finalizer):
    return %"$(body.repr()) $(finalizer.repr())";
  return "none";
}

int main(void) {
  Macro raised = $raised2, indexed = $indexed2, returned = $returned2;
  List statements = %(
    (raise E (args K V)) (seq (raise E (args K V))) (seq (raise E) extra)
    (at P (raise E (args K V))) (src P (raise E (args K V)))
    (at P (src Q (seq (raise E (args K))))) (raise (at P E) (args))
    (raise E (at P (args K))) (raise E (args K) extra) (stmnt E)
    (at P (stmnt E)) (seq (stmnt E)) () ("raise" E (args)));
  foreach (List node, statements)
    printf("%s | %s\n", inline_raise(node), generic_raise(node));
  List pending = raised(%(expr ("int") (literal (int) "1")), %());
  printf("%s | %s\n", inline_raise(pending), generic_raise(pending));
  List expressions = %(
    (expr T (index R S)) (expr T (at P (index R S)))
    (at P (expr T (index R S))) (index R S) (expr T (index R))
    (expr T (call R S)) (expr T (at P (call R S))) (expr T)
    (expr T R) (expr T ()) (expr T ("index" R S)) (stmnt (expr T R))
    (expr (<macro-expr>) (expr T (index R S)))
    (expr (<macro-expr>) (expr T (call R S))) (src P (expr T (index R S))));
  foreach (List node, expressions)
    printf("%s | %s\n", inline_index(node), generic_index(node));
  List shelled = indexed(%(expr T R), %(expr T S));
  printf("%s | %s\n", inline_index(shelled), generic_index(shelled));
  List returns = %(
    (return) (seq (return)) (at P (return)) (return T V) (return ())
    (stmnt E) (seq (return) (return)));
  foreach (List node, returns)
    printf("%s | %s\n", inline_return(node), generic_return(node));
  List returning = returned();
  printf("%s | %s\n", inline_return(returning), generic_return(returning));
  List tries = %(
    (try B () F) (seq (try B () F)) (try B (at P ()) F) (try B (X) F)
    (try B F) (at P (try (at Q B) () F)) (stmnt E));
  foreach (List node, tries)
    printf("%s | %s\n", inline_try(node), generic_try(node));
  return 0;
}
