/*  alias-included-conflict.x -- an included alias owns its name

    A public file-scope alias that an include delivers belongs to the
    including file's file scope, so a later declaration of its name there
    conflicts with it, as it would with an alias written in this file.
*/

#include "x2c.x"
#include "alias-included/shared.x"

Config config = { 7 };
int level = 4;

int main(void) { return level; }
