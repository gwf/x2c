/*  generate.x -- the generated header and source of one unit

    This module owns a unit's generated files: it splits the lowered AST into
    header and source without changing source order, gives the source its
    once-only initialization and static prototypes, wraps the header in its
    guard, and publishes both with the unit's interface. The definition rows
    the interface lists, and `--dump-definitions` prints, come from the same
    lowered AST.
*/
#pragma once
#include "compiler.x"
#include "grammar.x"
#include "ast-rewrite.x"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cache.x"
#include "collect.x"
#include "format.x"
#include "emit.x"
#include "utils.x"

/* file initialization

   Queued initialization runs once per file, behind a guard. Each function
   receives its entry setup from one decision, which the header's cache
   initialization also uses. */

/** Holds one region's initialization. `guard` is set once the region has
    initialized, and `entry` is the function a guarded entry calls. In the
    source, `initializer` names the type initializer, `shutdown` registers
    the unit's shutdown function, `synthetic` is the synthetic initializer or
    NULL, and `reachable` holds the entries a cache-only file guards, or is
    NULL when every public entry is guarded. */
typedef struct Init {
  Compiler c, String initializer, List guard, entry, shutdown, synthetic;
  Map reachable;
} Init;

module {
  "generate/output.x",
  "generate/projection.x",
  "generate/initialization.x",
  "generate/dependencies.x",
  "generate/definitions.x",
}
