#include "x2c.x"

static int saved = 7;
static int captured = saved;
#include "header-promoted-include-types.x"
typedef PromotedIncludeValue PromotedIncludeAlias;

int main(void) {
  PromotedIncludeAlias value = saved;
  printf("%d %d\n", captured, value);
  return captured != 7 || value != 42;
}
