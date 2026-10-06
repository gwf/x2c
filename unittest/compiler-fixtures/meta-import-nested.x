#pragma once

/*  meta-import-nested.x -- a `meta` function behind a second import

    `meta-import-defs.x` imports this file, so its definition reaches
    the consuming unit through two levels of macro import rather than one.
    See `plans/meta-functions.md`.
*/

meta String mi_dashed(String path) => path.replace(".", "-");
