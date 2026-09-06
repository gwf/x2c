#include "x2c.x"

$(import "macro-embed-text-definition/embed.xmacro")

int main(void) {
  printf("[%s]\n", $embed.definition());
  printf("[%s]\n", $embed.caller("macro-embed-text-data.txt"));
  printf("[%d]\n", $embed.empty().len());
  return 0;
}
