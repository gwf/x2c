/*  cstar-annotations.x -- the erased annotation marker.

    Every inner `$cstar.*` annotation expands to a call of this marker so its
    position survives in the captured body; `$cstar.verify` erases every
    marker it finds, so the marker never reaches C.

    A verified unit does not need this declaration: x2c accepts the
    undeclared marker in the expression it is erased from. Including it makes
    an annotation outside a verified function a link error naming
    `cstar_marker` instead of an implicit-declaration compile error.
*/

#pragma private

void cstar_marker(int id);
