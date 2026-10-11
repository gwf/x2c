/* A program's function rule is offered the definitions the source writes,
   including those a program's own meta code places or its rule returns,
   and nothing the compiler writes: not a defer's cleanup callback, a
   lifted lambda or its adapter, a protocol's forwarding member, or the
   definition a shipped function rule returns for a source one. The
   statements such a definition holds from the source still reach the
   program's statement rules. */

#include "x2c.x"
#include "rewrite.x"
#include "meta.x"

#include <stdio.h>

static int switches = 0;

macro Unit $any_function(Function $function) { $function }

$rewrite($any_function)
/* Records the name of each function offered, then declines it. */
meta Code note_function(Code function) {
  String name = Code.name(function);
  x2c_place(%(unit-init), $!{ printf("offered %s\n", $name); });
  return function;
}

$rewrite($switched)
/* Each switch is counted, then runs as written. */
meta Code count_switch(Code node) {
  return $!{ { switches++; $node } };
}

/* A program's meta code places a helper among the unit's support. */
meta static List place_helper(void) {
  List name = x2c_ident("placed_helper");
  x2c_place(
    %(unit-support key), $!Unit{ static int $name(void) { return 7; } });
  return %(expr (int) (call (expr () (ident $name)) (args)));
}
macro Expression $helper() => $place_helper();

typedef struct Shape { double r; } *Shape;
protocol Shape(T) {
  double T.area(T);
}
double Shape.area(Shape s) => s.r * s.r;

/* Disk's area is a forwarding member the protocol component writes. */
typedef struct Disk { double r; } *Disk;
Shape Disk.shape(Disk d) => (Shape) d;
protocol Shape(Disk);

/* A Ring's own rule writes its members, which are the program's. */
typedef struct Ring { double outer; } *Ring;
Shape Ring.shape(Ring r) => (Shape) r;
protocol Shape(Ring);

$rewrite(%(conform ("Shape") ("Ring") *))
meta Code ring_members(Code node) {
  List area = x2c_ident("Ring_area");
  return $!Unit{ double $area(Ring r) { return r.outer * 2; } };
}

static int cleaned = 0;

/* The defer's finalizer becomes a cleanup callback. */
static int guarded(int n) {
  {
    defer switch (n) { default: cleaned += n; }
    n++;
  }
  return n;
}

int main(void) {
  struct Disk disk = {2.0};
  struct Ring ring = {1.5};
  Disk d = &disk;
  Ring r = &ring;
  int base = 3;
  Func plain = %!(Var n) => {
    switch (n.int()) { default: return n.int() * 2; }
  };
  Func shared = %!(Var n) using &base => n.int() + base;
  printf(
    "%g %g %d %ld %ld %d %d\n", d.area(), r.area(), guarded(4),
    plain(1).integer(), shared(1).integer(), cleaned, $helper());
  printf("%d\n", switches);
  return 0;
}
