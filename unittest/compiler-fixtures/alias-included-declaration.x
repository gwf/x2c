/*  alias-included-declaration.x -- an alias, then an include that declares
    its name

    A file-scope alias owns its name in this file's file scope, so an
    include that declares the name conflicts at its include line, as a
    declaration written here would.
*/

#include "x2c.x"

alias 5 as declared_kind;

#include "alias-included/declared.x"

int main(void) { return declared_kind; }
