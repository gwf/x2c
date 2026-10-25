/*  unalias-included.x -- removing an alias an include delivered

    This file removes an included alias and declares its name itself. An
    included file that aliases a name and removes it again leaves nothing
    for this file to remove.
*/

#include "x2c.x"
#include "alias-included/shared.x"
#include "alias-included/transient.x"

Config config = { 7 };

unalias level;
int level = 4;
int answer = 5;

int main(void) { return level + answer + doubled; }
