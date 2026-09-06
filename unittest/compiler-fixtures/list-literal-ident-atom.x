#include "x2c.x"

/* The atom `ident` is also the compiler's AST tag for a variable reference.
   A list literal holding it is still constant data and must fold to a
   file-scope cache entry, in any position. A literal that really does hold
   a reference must stay live. */

static List head_atom(void)    { return %(ident (x)); }
static List nested_atom(void)  { return %(a (ident y)); }
static List tail_atom(void)    { return %(a ident); }
static List bare_atom(void)    { return %(ident); }
static List reference(int n)   { return %(count $n); }

int main(void) {
  printf("%s %s %s %s %s %d\n",
         head_atom().repr().str(), nested_atom().repr().str(),
         tail_atom().repr().str(), bare_atom().repr().str(),
         reference(7).repr().str(), head_atom() == head_atom());
  return 0;
}
