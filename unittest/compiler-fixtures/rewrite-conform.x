#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

typedef struct Shape { double r; } *Shape;
protocol Shape(T) {
  double T.area(T);
  double T.scale(T, double);
}
double Shape.area(Shape s) => s.r * s.r;
double Shape.scale(Shape s, double k) => s.r * k;

/* Disk's members forward to Shape through the shipped rule. */
typedef struct Disk { double r; } *Disk;
Shape Disk.shape(Disk d) => (Shape) d;
protocol Shape(Disk);

/* A Ring's own rule writes its members instead. */
typedef struct Ring { double outer, inner; } *Ring;
Shape Ring.shape(Ring r) => (Shape) r;
protocol Shape(Ring);

$rewrite(%(conform ("Shape") ("Ring") *))
/* A Ring's area is the outer disk's less the inner one's, and its scale
   reads the outer radius. */
meta Code ring_members(Code node) {
  List area = x2c_ident("Ring_area"), scale = x2c_ident("Ring_scale");
  return $!Unit{
    double $area(Ring r) { return r.outer * r.outer - r.inner * r.inner; }
    double $scale(Ring r, double k) { return r.outer * k; }
  };
}

/* A Var participant's descriptor still comes from the shipped rule. */
typedef struct Badge { long id; } *Badge;
Var Badge.var(Badge b) => Var.new(<badge>, b);
Badge Var.badge(Var v) => (Badge) v.pointer();
String Badge.str(Badge b) => %"badge $(b.id)";
protocol Var(Badge);

int main(void) {
  struct Disk disk = {2.0};
  struct Ring ring = {3.0, 1.0};
  struct Badge badge = {7};
  Disk d = &disk;
  Ring r = &ring;
  Var boxed = (Badge) &badge;
  printf("%g %g\n", d.area(), d.scale(3.0));
  printf("%g %g\n", r.area(), r.scale(3.0));
  printf("%s\n", boxed.str());
  return 0;
}
