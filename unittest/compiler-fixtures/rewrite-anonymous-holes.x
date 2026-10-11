/* Anonymous holes in a macro-valued case match what named holes match,
   in a rule and on a List built at run time. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int counted = 0;

$rewrite($switched)
/* Each switch on an int is counted, then switches as written. */
meta Code count_switch(Code node) {
  match (node) case $switched(?, ?):
    match (node) case %(switch (expr (int) ?) ?):
      return $!{ { counted++; $node } };
  return node;
}

macro Stmt $cases(Expr $subject, Stmt @arms) { switch ($subject) { @arms } }

static int shapes(List code) {
  int found = 0;
  match (code) case $switched(?, ?): found |= 1;
  match (code) case $cases(?, *): found |= 2;
  if (Macro.matches($switched, code, %(? ?))) found |= 4;
  if (Macro.matches($cases, code, %(? *))) found |= 8;
  return found;
}

int main(void) {
  int n = 2;
  switch (n) { case 2: n = 3; }
  List code = %(switch (expr (int) (literal (int) "1")) (block));
  printf("%d %d %d\n", n, counted, shapes(code));
  return 0;
}
