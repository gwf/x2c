#include "x2c.x"

// Each wide family boxes into the region, which ends before the return.
Var boxed_long(long big) {
  auto {
    Var v = big;
    return v;
  }
  return 0;
}

Var boxed_unsigned_long(unsigned long big) {
  auto {
    Var v = big;
    return v;
  }
  return 0;
}

Var boxed_long_long(long long big) {
  auto {
    Var v = big;
    return v;
  }
  return 0;
}

Var boxed_unsigned_long_long(unsigned long long big) {
  auto {
    Var v = big;
    return v;
  }
  return 0;
}

Var boxed_long_double(long double big) {
  auto {
    Var v = big;
    return v;
  }
  return 0;
}

// A returned or pushed number is boxed in the region too.
Var returned_long(long big) {
  auto {
    return big;
  }
  return 0;
}

void pushed_long(Array out, long big) {
  auto {
    out.push(big);
  }
}

// A List literal item and an element store are boxed before the check.
List listed_long_long(long long big) {
  auto {
    List items = $(big);
    return items;
  }
  return NULL;
}

void stored_long_long(Array out, long long big) {
  auto {
    out[0] = big;
  }
}

// A helper with no region boxes into its caller's region.
Var boxed_by_caller(long big) => big;

Var boxed_by_helper(long big) {
  auto {
    Var v = boxed_by_caller(big);
    return v;
  }
  return 0;
}

// An int or a double fits inside the Var and allocates nothing.
Var inline_int(int small) {
  auto {
    Var v = small;
    return v;
  }
  return 0;
}

Var inline_double(double small) {
  auto {
    Var v = small;
    return v;
  }
  return 0;
}

void pushed_int(Array out, int small) {
  auto {
    out.push(small);
  }
}

// A box made while the caller's Scope is active belongs to that Scope.
Var kept_long(long big, Scope *keep) {
  Var v;
  auto (keep) {
    v = big;
  }
  return v;
}
