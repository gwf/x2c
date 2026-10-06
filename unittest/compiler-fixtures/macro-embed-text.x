#include "x2c.x"

#include "macro-embed-text-definition/embed.x"

int main(void) {
  printf("[%s]\n", $embed.definition());
  printf("[%s]\n", $embed.caller("macro-embed-text-data.txt"));
  printf("[%d]\n", $embed.empty().len());
  return 0;
}
