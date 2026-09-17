#include "x2c.x"

/* A public object is declared `extern` in the header and defined once here,
   and an initializer that has to run moves into unit initialization. A
   prototype names no storage, so it stays whole in the header. */
int file_object_counter = 0;
int file_object_pending;
const int file_object_limit = 7;
Map file_object_registry = {};
double file_object_scale(double factor);

/* A const file object with a runtime initializer loses the C qualifier so
   the deferred assignment is legal. */
static const String file_object_name = "hi";
static const String file_object_words[] = {"a", "b"};
static List const file_object_items = %(1 2);
static const char *file_object_text = String.new("xyz");

int main(void) {
  file_object_counter = 3;
  file_object_registry["k"] = 1;
  String name = file_object_name;
  String second = file_object_words[1];
  List items = file_object_items;
  printf("%d %d %d %d %d %d %d %s\n",
         file_object_counter, file_object_pending, file_object_limit,
         (int) file_object_registry.len(), name.len(), second.len(),
         items.len(), file_object_text);
  return 0;
}
