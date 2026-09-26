/*  meta-c-semantics.x -- C operations a meta body evaluates as C does

    Indexing a real pointer reads and writes native bytes, while a pointer
    holding a local C array still indexes its Array. `NULL`, `true` and
    `false` are the preprocessor names C code writes, and a pointer compares
    with `NULL` and tests false at the null address. A typed `foreach`
    output converts each element. `bool` and int-sized enum objects have
    native layouts, so their fields and addresses work. A value reaching
    `bool` becomes 0 or 1 and compares as the int it holds. `strncmp` takes
    its length as `size_t`. Each probe prints its compile-time and run-time
    answers.
*/

#include "x2c.x"
#include <stdbool.h>

enum Color { RED, GREEN, BLUE };
enum Sign { NEGATIVE = -5, POSITIVE = NEGATIVE + 10, AFTER };

struct Flags { bool on; enum Color color; char tail; int count; };
struct Node { int value; struct Node *next; };
struct Signed { enum Sign sign; int tail; };

$(import "meta-c-semantics.xmacro")

/* A switch on a bool is legal C that compilers warn about. */
#pragma GCC diagnostic ignored "-Wswitch-bool"

int main(int argc, char **argv) {
  (void) argv;
  int offset = argc - 1;
  printf("%d %d\n", $pointer_index(0), pointer_index(offset));
  printf("%d %d\n", $preprocessor_names(0), preprocessor_names(offset));
  printf("%d %d\n", $typed_foreach(0), typed_foreach(offset));
  printf("%d %d\n", $bool_values(0), bool_values(offset));
  printf("%d %d\n", $native_fields(0), native_fields(offset));
  printf("%d %d\n", $bool_compare(0), bool_compare(offset));
  printf("%d %d\n", $null_pointers(0), null_pointers(offset));
  printf("%d %d\n", $signed_enum(0), signed_enum(offset));
  printf("%d %d\n", $string_prefix(0), string_prefix(offset));
  return 0;
}
