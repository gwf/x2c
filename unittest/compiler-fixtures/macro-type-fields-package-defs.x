#pragma once

#include "x2c.x"

/* The check lives apart from the package import, so its meta group does
   not need the package's headers. */
meta List same_fields(Type type, List expected, String message) {
  List actual = Type.fields(type);
  if (!actual.equal(expected))
    x2c_diagnostic_fail(message, %($(actual.repr())));
  return %();
}
