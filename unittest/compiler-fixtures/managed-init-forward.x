#include "x2c.x"

/* A forwarding macro, parentheses, and a template keep `$auto` the
   complete initializer, and each managed declarator of a comma declaration
   is released after its own initialization. */

static int released = 0;

typedef struct Probe { int id; } *Probe;
static Probe Probe.new(int id) {
  Probe probe = calloc(1, sizeof(struct Probe));
  probe.id = id;
  return probe;
}
static void Probe.cleanup(Probe probe) {
  printf("release %d\n", probe.id);
  released++;
  free(probe);
}
protocol Cleanup(Probe);

macro Expression $id(Expr $value) => $value;
macro Stmt $managed(Expr $id) {
  Probe made = $auto(Probe.new($id));
  printf("made %d\n", made.id);
}

int main(void) {
  {
    Probe first = $id($auto(Probe.new(1))), plain = Probe.new(2),
      second = ($auto(Probe.new(3)));
    printf("%d %d %d\n", first.id, plain.id, second.id);
    Probe.cleanup(plain);
    $managed(4);
  }
  printf("released %d\n", released);
  return 0;
}
