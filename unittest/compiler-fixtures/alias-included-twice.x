/*  alias-included-twice.x -- two includes alias one name

    Each include delivers its aliases into this file's file scope, so the
    second alias of a name conflicts at its include line.
*/

#include "x2c.x"
#include "alias-included/shared.x"
#include "alias-included/other.x"

int main(void) { return doubled; }
