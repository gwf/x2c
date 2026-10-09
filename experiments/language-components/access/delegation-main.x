#include "delegation.x"

static int calls;
static Wrapper current;
static Wrapper next(void) { calls++; return current; }

int main(void) {
  Wrapper wrapper = {{7}};
  current = wrapper;
  int value = next().read(2);
  wrapper.bump(3);
  Unrelated other = {0};
  int unrelated = other.read(2);
  printf("delegation: %d %d %d once: %d unrelated: %d\n",
    value, wrapper.part.value, wrapper.own(), calls, unrelated);
  return value != 9 || wrapper.part.value != 10 || calls != 1 || unrelated != 999;
}
