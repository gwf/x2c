/*  comptime-declines-meta-enum.x -- an enum constant in a `meta` body

    An enumerator's value lives only in the enum declaration it was written
    in: the symbol table keeps the enum type and the fact that the name is an
    enumerator, never the number. The lowering read it as file-scope state
    and answered zero, so a macro calling this function got a silently wrong
    value. It is refused by its own name instead.
    See `plans/meta-functions.md`.
*/

#include "x2c.x"
#include "meta.x"

enum { K = 10 };

meta static List de_literal(void) => x2c_literal_int(K);

int main(void) { return 0; }
