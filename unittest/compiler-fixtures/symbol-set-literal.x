#include "x2c.x"

static SymbolSet values = %<<foo bar <odd/val> quux>>;

static SymbolSet same_values(void) {
  return %<<foo bar <odd/val> quux>>;
}

int main(void) {
  SymbolSet empty = %<<>>;
  List ordinary = %(foo bar);
  int ordered = values.len() == 4 &&
                values.index(<foo>) == 0 &&
                values.index(<odd/val>) == 2 &&
                values.index(<missing>) == -1 &&
                values.getindex(1) == <bar> &&
                values.getindex(-1) == <quux> &&
                values.getindex(4) == 0 &&
                values.getindex(-5) == 0 &&
                same_values().index(<odd/val>) == 2;
  int membership = values.contains(<bar>) &&
                   !values.contains(<missing>) &&
                   empty.len() == 0 && empty.index(<foo>) == -1;
  int atoms = ordinary.getindex(0).is_atom() &&
              ordinary.getindex(1).is_atom();
  int iteration = 0;
  foreach(Symbol symbol, values)
    iteration += values.index(symbol) + 1;
  printf("%d %d %d %d\n", ordered, membership, atoms, iteration);
  return ordered && membership && atoms && iteration == 10 ? 0 : 1;
}
