#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int declarations = 0, reads = 0;

$rewrite(%(dstrdecl ? (targets *) ?))
/* A named destructuring declaration is counted, then declared as
   written. */
meta Code count_declaration(Code node) {
  return $!{ declarations++; $node };
}

$rewrite(%(stmnt (expr ? (dstrasgn *))))
/* A two-target assignment statement assigns its targets in reverse; any
   other is destructured as written. */
meta Code reverse_statement(Code node) {
  match (node)
    case %(stmnt (expr ? (dstrasgn (targets ?first ?second) ?source))): {
      Code earlier = first, later = second;
      return $!{
        {
          List values = $source;
          $earlier = values[1];
          $later = values[0];
        }
      };
    }
  return node;
}

$rewrite(%(expr ? (dstrasgn *)))
/* An assignment expression counts its read and keeps its value. */
meta Code count_value(Code node) {
  return $!(({ reads++; $node; }));
}

int main(void) {
  Var (a, b) = %(1 2);
  (a, b) = %(3 4);
  printf("%ld %ld\n", a.integer(), b.integer());
  List kept = (a, b) = %(5 6);
  printf("%ld %ld %d %d %d\n", a.integer(), b.integer(), declarations,
         reads, kept.len());
  return 0;
}
