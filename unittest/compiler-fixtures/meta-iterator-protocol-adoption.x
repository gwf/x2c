#include "x2c.x"

/* The existing Var->Iter protocol keeps the caller's destination; this is
   deliberately not a parallel iterator construction path. */
meta int protocol_adoption_probe(int offset) {
  List input = %(1 2 3);
  struct Iter storage;
  Iter values = Var.iter(input, &storage);
  Var first, second, third, extra;
  if (!values.try_next(first) || !values.try_next(second) ||
      !values.try_next(third) || values.try_next(extra)) return -1;
  return first.int() + second.int() + third.int() + offset;
}

/* A boxed <iter> unboxes to the same iterator. */
meta int iter_round_trip(int offset) {
  struct Iter storage;
  Var boxed = Var.iter(%(1 2 3), &storage);
  Iter again = boxed.as_iter();
  return again.sum().int() + offset;
}

/* The fallback iterator is empty, whether the caller or the compiler
   supplies its storage. */
meta int fallback_counts(int offset) {
  struct Iter storage;
  Var boxed = %(4 5);
  Iter given = Var.fallback_iter(boxed, &storage);
  return given.count() * 10 + boxed.fallback_iter().count() + offset;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $protocol_adoption_probe(0),
         protocol_adoption_probe(argc - 1));
  printf("%d %d\n", $iter_round_trip(0), iter_round_trip(argc - 1));
  printf("%d %d\n", $fallback_counts(0), fallback_counts(argc - 1));
  return 0;
}
