/*  alias-included-declaration-imported.x -- an included alias, then an
    include that declares its name

    An alias that an include delivers belongs to this file's file scope, so
    a later include that declares its name conflicts at its include line.
*/

#include "x2c.x"
#include "alias-included/shared.x"
#include "alias-included/declared.x"

int main(void) { return level; }
