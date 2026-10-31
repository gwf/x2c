#include "macro-expand-provider.x"

int main(void) {
  printf("%d %d\n", mapped_answer(), mapped_other());
  return mapped_answer() + mapped_other() != 49;
}
