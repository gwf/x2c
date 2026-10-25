/*  alias-included-after.x -- an alias, then an include of the same name

    The include delivers its alias at its own line, where this file already
    aliases the name at file scope.
*/

#include "x2c.x"

alias 1 as level;

#include "alias-included/shared.x"

int main(void) { return level; }
