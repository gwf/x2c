#include "x2c.x"

/* Outside an expansion a String path is relative to the calling file. */
String value = $x2c_embed_text("macro-embed-text-data.txt");

int main(void) {
  printf("%s", value.str());
  return 0;
}
