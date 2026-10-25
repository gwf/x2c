#include "x2c.x"

static typedef struct OrdinaryLeaf { int value; } OrdinaryLeaf;
static typedef struct OrdinaryPayload { OrdinaryLeaf leaf; } OrdinaryPayload;
static typedef OrdinaryPayload OrdinaryAlias;
static typedef struct OrdinarySecret { int hidden; } OrdinarySecret;
static typedef struct OrdinaryInlineOnly { int value; } OrdinaryInlineOnly;

OrdinaryAlias ordinary_copy(OrdinaryAlias value) => value;

inline int ordinary_inline_value(int value) {
  OrdinaryInlineOnly item = {value};
  return item.value;
}

meta static int field_count(Code value) =>
  Type.fields(Code.type(value)).len();

static macro Expression $ordinary.fields(Expr $value) =>
  $field_count($value);

int main(void) {
  OrdinaryAlias visible = {{13}};
  OrdinarySecret secret = {17};
  printf("%d %d %d\n", $ordinary.fields(visible),
    $ordinary.fields(secret),
    ordinary_inline_value(ordinary_copy(visible).leaf.value));
  return 0;
}
