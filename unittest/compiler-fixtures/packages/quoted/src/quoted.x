// A type name quoted by a meta function in another package file names the
// package's type where the generated code lands.
#include "x2c.x"

typedef struct Field { size_t capacity; } *Field;

#include "quoted-generate.x"

size_t field_capacity(Field field) => field.capacity;

$quoted.reader("room");
