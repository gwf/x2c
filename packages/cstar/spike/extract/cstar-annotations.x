/*  cstar-annotations.x -- the erased annotation marker.

    Every `$cstar.*` annotation expands to a call of this marker so its
    position survives in the parsed body.  `$cstar.verify` erases every
    marker it finds, so the declaration never needs a definition.
*/

#pragma private

void cstar_marker(int id);
