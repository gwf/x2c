#include "x2c.x"

static typedef struct OrdinaryLeaf { int value; } OrdinaryLeaf;
static typedef struct OrdinaryPayload { OrdinaryLeaf leaf; } OrdinaryPayload;
static typedef OrdinaryPayload OrdinaryAlias;
static typedef struct OrdinarySecret { int hidden; } OrdinarySecret;

OrdinaryAlias ordinary_copy(OrdinaryAlias value) => value;

static macro Expression $ordinary.fields(Expr $value) =>
  $(x2c.literal.int
    (length (x2c.type.fields (x2c.syntax.type $value))));

int main(void) {
  OrdinaryAlias visible = {{13}};
  OrdinarySecret secret = {17};
  printf("%d %d %d\n", $ordinary.fields(visible),
    $ordinary.fields(secret), ordinary_copy(visible).leaf.value);
  return 0;
}
