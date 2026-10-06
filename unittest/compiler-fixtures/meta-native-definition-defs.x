#pragma once

/* meta-native-definition-defs.x -- the ordinary meta provider */

typedef int native;

/* Followed by no declaration, `native` after `meta` is a type name. */
meta native twice(native x) => x * 2;
