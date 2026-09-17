/*  import-runtime-include.x -- a package's runtime includes expose no
    unprefixed declarations. Its public path.x include crosses as a C
    header does, so the consumer can use the package's Path result.
*/
#pragma once

import "runtimeinc" as r;

int runtime_include(void);

#pragma private

int runtime_include(void) {
  Path home = r.home_path();
  return r.twice((int) home.basename().len());
}
