#include <assert.h>

meta static List responses(void) =>
  %((200 "OK") (404 "Not Found") (503 "Unavailable"));

meta static int response_count(void) => responses().len();

meta static List setup(void) {
  Array steps = [];
  int i = 0;
  foreach (List row in responses()) {
    steps.push($!{
      codes[$i] = $(row[0]);
      labels[$i] = $(row[1]);
    });
    i++;
  }
  List statements = steps.list_free();
  return $!{ @statements };
}

int main(void) {
  int codes[$response_count()];
  String labels[$response_count()];
  $setup();
  for (int i = 0; i < $response_count(); i++)
    printf("%d: %s\n", codes[i], labels[i]);
  assert(codes[1] == 404 && labels[1] == "Not Found");
  return 0;
}
