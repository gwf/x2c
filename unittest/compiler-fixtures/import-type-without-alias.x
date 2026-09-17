/*  A package type is reachable only through its import alias. Naming it bare
    in a parameter list used to read as a parenthesized declarator and blame
    the parameter name. */

import "geo" as g;

double Vec.scaled(Vec v, double k) { return v.norm() * k; }

int main(void) { return 0; }
