#include "x2c.x"
#include "meta.x"

/* A kind name wins over a type name: `$!Type{ ... }` names the Type kind,
   not a typed quotation of type `Type`, which is `$!(Type){ ... }`. No
   quotation builds the Type kind. */
int main(void) {
  List type = $!Type{ int };
  return type != NULL;
}
