/*  geo.x -- toy geometry package for package-mode translation fixtures.

    Vec owns its heap records; VecPair aggregates two records by value.
*/
#pragma once

typedef struct VecData { double x, y; } *Vec;

typedef struct VecPair { struct VecData a, b; } VecPair;
typedef List Chain;
typedef Chain ChainLeaf;

Vec Vec.new(double x, double y);
double Vec.norm(Vec v);
double span(VecPair pair);
Var Vec.var(Vec v);
Vec Var.vec(Var value);
Vec double.vec(double scale);
Vec Vec.mul(Vec a, Vec b);
protocol Var(Vec);
protocol Iter(Vec);
Self Chain.rest(Self values);
int ChainLeaf.leaf_len(ChainLeaf values);

#pragma private

#include <math.h>

typedef double Magnitude;

Vec Vec.new(double x, double y) {
  Vec v = Scope.malloc(sizeof(struct VecData));
  v.x = x; v.y = y;
  return v;
}

double Vec.norm(Vec v) {
  Magnitude m = sqrt(v.x * v.x + v.y * v.y);
  return m;
}

double span(VecPair pair) {
  return sqrt(pair.a.x * pair.a.x) + sqrt(pair.b.y * pair.b.y);
}

Var Vec.var(Vec v) { return (Var) { .p64 = v }; }

Vec Var.vec(Var value) { return value.p64; }

// A double beside a Vec scales both components.
Vec double.vec(double scale) { return Vec.new(scale, scale); }

Vec Vec.mul(Vec a, Vec b) { return Vec.new(a.x * b.x, a.y * b.y); }

Self Chain.rest(Self values) { return values.cdr(); }
int ChainLeaf.leaf_len(ChainLeaf values) { return values.len(); }

// Iterating a Vec yields its two components, in order.
static int _vec_next(Iter iter, Var *out) {
  int index = iter.state.integer();
  if (index >= 2) return 0;
  iter.state = index + 1;
  *out = index ? iter.obj.vec().y : iter.obj.vec().x;
  return 1;
}

Iter Vec.iter(Vec v, Iter dest) {
  return dest.init(v, _vec_next, 0);
}
