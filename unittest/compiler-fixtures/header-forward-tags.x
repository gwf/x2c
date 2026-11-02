#include "x2c.x"

void forward_struct(struct Incomplete *value);
void forward_union(union IncompleteUnion *value);
void defined(struct Defined *value) { (void) value; }
struct Complete { int value; };
int completed(struct Complete *value) => value.value;
void reused(struct Incomplete *value);

int main(void) {
  struct Complete value = {7};
  printf("%d\n", completed(&value));
  return 0;
}
