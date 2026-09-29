#include "x2c.x"
#include "meta.x"
$(import "../../src/grammar.xmacro")

static List projected_call(Var value) {
  match (value)
    case $source_pattern($called, %(?callee *rows)): {
      match (rows) case %((expr ? ())): rows = NULL;
      return %($callee $rows);
    }
  return NULL;
}

static List projected_assignment(Var value) {
  match (value)
    case $source_pattern($assigned, %(?target ?stored)): {
      match (target) case %(bind *): return NULL;
      return %($target $stored);
    }
  return NULL;
}

static List projected_index(Var value) {
  match (value)
    case $source_pattern($indexed, %(?base ?selector)):
      return %($base $selector);
  return NULL;
}

static void check(List input, List callee, List arguments) {
  List parts = projected_call(input);
  assert(parts && parts.car().list() == callee &&
         parts.cadr().list() == arguments);
}

static void check_assignment(List input, List target, List stored) {
  List parts = projected_assignment(input);
  assert(parts && parts.car().list() == target &&
         parts.cadr().list() == stored);
}

int main(void) {
  List binding = %(binding 7 "callee");
  List callee = %(expr ((func ((int))) int) (ident $binding));
  List first = %(expr (int) (literal (int) "1"));
  List second = %(expr (int) (literal (int) "2"));
  List arguments = %($first $second);
  List call = %(call $callee (args @arguments));
  check(call, callee, arguments);
  check(%(expr (int) $call), callee, arguments);
  List wrapped = %(at 1 $callee);
  check(%(call $wrapped (args @arguments)), wrapped, arguments);
  assert(!projected_call(%(at 1 $call)));
  List empty = %(call $callee (args (expr () ())));
  check(empty, callee, NULL);
  check(%(expr (int) $empty), callee, NULL);
  assert(!projected_call(%(expr (int) (ident $binding))));
  List target = %(expr (int) (ident $binding));
  List stored = %(expr (int) (literal (int) "3"));
  List assignment = %(op = $target $stored);
  check_assignment(assignment, target, stored);
  check_assignment(%(expr (int) $assignment), target, stored);
  assert(!projected_assignment(%(op =
    (bind $binding ()) $stored)));
  assert(!projected_assignment(%(expr (int)
    (op = (bind $binding ()) $stored))));
  assert(!projected_assignment(%(expr (int) (ident $binding))));
  List index = %(index $target $stored);
  List indexed = projected_index(index);
  assert(indexed.car().list() == target && indexed.cadr().list() == stored);
  indexed = projected_index(%(expr (int) $index));
  assert(indexed.car().list() == target && indexed.cadr().list() == stored);
  indexed = projected_index(%(index $wrapped $stored));
  assert(indexed.car().list() == wrapped &&
         indexed.cadr().list() == stored);
  assert(!projected_index(%(getindex $target $stored)));
  assert(!projected_index(%(expr (int) (getindex $target $stored))));
  printf("source call, index, and assignment projections passed\n");
  return 0;
}
