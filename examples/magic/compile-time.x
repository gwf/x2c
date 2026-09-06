#include <assert.h>
// One table supplies both wire codes and readable labels.
$(defun responses ()
  '((200 "OK") (404 "Not Found") (503 "Unavailable")))

static const int codes[] = $(x2c.expr.composite
  (map (lambda (row) (x2c.literal.int (car row)))
       (responses)));

int main(void) {
String labels[] = $(x2c.expr.composite
  (map (lambda (row) (x2c.literal.string (cadr row)))
       (responses)));

// The generated program uses ordinary C arrays.
for (size_t i = 0; i < sizeof(codes) / sizeof(*codes); i++)
  printf("%d: %s\n", codes[i], labels[i]);
assert(codes[1] == 404 && labels[1] == %"Not Found");
return 0;
}
