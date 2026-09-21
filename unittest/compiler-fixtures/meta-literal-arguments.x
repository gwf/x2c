/* The Lisp literal adapters preserve their argument checks while sharing
   syntax construction with the runtime-capable meta bodies. */
#include "x2c.x"

macro Expression $bad.string() => $(x2c.literal.string 7);
macro Expression $bad.number() => $(x2c.literal.int "abc");
macro Expression $bad.symbol() => $(x2c.literal.symbol 7);

String bad_string(void) => $bad.string();
int bad_int(void) => $bad.number();
Symbol bad_symbol(void) => $bad.symbol();
