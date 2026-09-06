#include "x2c.x"

int filtered(int mode) {
  try {
    if (mode == 1)
      raise %(alloc-fail (bytes $mode));
    if (mode == 2)
      raise %(bad-arg (value $mode));
  }
  catch %(alloc-fail * (bytes ?count) *):
    return count.int();
  catch %(bad-arg *rest): {
    return rest.len();
  }
  catch:
    return -1;
  finally {
    mode++;
  }
  return 0;
}
