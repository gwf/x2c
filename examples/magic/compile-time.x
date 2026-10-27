#include <assert.h>

static const int codes[] = $column(0);

int main(void) {
String labels[] = $column(1);

// The generated program uses ordinary C arrays.
for (size_t i = 0; i < sizeof(codes) / sizeof(*codes); i++)
  printf("%d: %s\n", codes[i], labels[i]);
assert(codes[1] == 404 && labels[1] == "Not Found");
return 0;
}

// The compiler runs `column` and inserts a C initializer built from the table.
meta static List column(int n) {
  Array cells = [];
  foreach (List row in responses()) cells.push(row[n]);
  List items = cells.list_free();
  return $!( { @items } );
}

// One table supplies both wire codes and readable labels.
meta static List responses(void) =>
  %((200 "OK") (404 "Not Found") (503 "Unavailable"));
