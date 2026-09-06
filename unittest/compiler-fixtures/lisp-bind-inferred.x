#include "x2c.x"

typedef unsigned char Byte;
typedef String Text;

static Byte increment(Byte value) {
  return value + 1;
}

$lisp.binding(sample, "echo")
static Text echo(Text value) {
  return value;
}

void install_bindings(Lisp lisp) {
  $lisp.bind(lisp, "increment", increment);
  $lisp.install(lisp, sample);
}
