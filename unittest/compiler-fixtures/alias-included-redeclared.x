/*  alias-included-redeclared.x -- an included alias, then the same name

    An alias that an include delivers belongs to this file's file scope, so
    a later alias of its name conflicts, whether or not a use has read the
    included alias first.
*/

#include "x2c.x"
#include "alias-included/shared.x"

Config config = { 7 };

static int used(void) { return level; }

alias 1 as level;

int main(void) { return used(); }
