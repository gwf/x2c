#include "x2c.x"

static List first = %(
  short
  VeryLongIdentifierName
  Mixed_Case_Identifier
  escaped\ atom
  <
  \x31
  \x31numeric-looking-long
  comment\x2F/looking-long
  <1>
);

static List second = %(
  short
  VeryLongIdentifierName
  Mixed_Case_Identifier
  escaped\ atom
  <
  \x31
  \x31numeric-looking-long
  comment\x2F/looking-long
  <1>
);

int main(void) {
  Lisp lisp = Lisp.new();
  unsigned cursor = 0;
  Var read = void;
  Symbol status = Lisp.read(
    lisp, first.repr(), &cursor, &read
  );
  printf("%d %d %s|%s|%s|%s|%s|%s|%s|%s\n",
         first == second, status == <value> && read.pointer() == first,
         first.getindex(0), first.getindex(1),
         first.getindex(2), first.getindex(3),
         first.getindex(4), first.getindex(5),
         first.getindex(6), first.getindex(7));
  Lisp.destroy(lisp);
  return 0;
}
