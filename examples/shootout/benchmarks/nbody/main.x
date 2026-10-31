/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 *
 * Adapted from Christoph Bauer's contributed C implementation.
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define PI 3.141592653589793
#define SOLAR_MASS (4 * PI * PI)
#define DAYS_PER_YEAR 365.24

class Vec3 { double x, y, z; };
class Body { Vec3 position, velocity; double mass; } *;

int main(int argc, char **argv) {
  Array bodies = _bodies();
  foreach (Body body in bodies) {
    body.velocity = body.velocity.scale(DAYS_PER_YEAR);
    body.mass *= SOLAR_MASS;
  }
  _offset_momentum(bodies);
  printf("%.9f\n", _energy(bodies));
  for (int i = atoi(argv[1]); i; i--) _advance(bodies, 0.01);
  printf("%.9f\n", _energy(bodies));
  return 0;
}

static void Body.init(Body body, Vec3 position, Vec3 velocity, double mass) {
  body.position = position;
  body.velocity = velocity;
  body.mass = mass;
}

static Array _bodies(void) => [
  Body.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, 0), 1),
  Body.new(
    Vec3.new(4.84143144246472090, -1.16032004402742839, -0.103622044471123109),
    Vec3.new(1.66007664274403694e-03, 7.69901118419740425e-03,
      -6.90460016972063023e-05), 9.54791938424326609e-04),
  Body.new(
    Vec3.new(8.34336671824457987, 4.12479856412430479, -0.403523417114321381),
    Vec3.new(-2.76742510726862411e-03, 4.99852801234917238e-03,
      2.30417297573763929e-05), 2.85885980666130812e-04),
  Body.new(
    Vec3.new(12.8943695621391310, -15.1111514016986312, -0.223307578892655734),
    Vec3.new(2.96460137564761618e-03, 2.37847173959480950e-03,
      -2.96589568540237556e-05), 4.36624404335156298e-05),
  Body.new(
    Vec3.new(15.3796971148509165, -25.9193146099879641, 0.179258772950371181),
    Vec3.new(2.68067772490389322e-03, 1.62824170038242295e-03,
      -9.51592254519715870e-05), 5.15138902046611451e-05)
];

static void _offset_momentum(Array bodies) {
  Vec3 momentum = Vec3.new(0, 0, 0);
  foreach (Body body in bodies)
    momentum = momentum.add_scaled(body.velocity, body.mass);
  Body sun = bodies[0];
  sun.velocity = momentum.scale(-1.0 / SOLAR_MASS);
}

static inline Vec3 Vec3.scale(Vec3 a, double s) =>
  Vec3.new(a.x * s, a.y * s, a.z * s);

static inline Vec3 Vec3.add_scaled(Vec3 a, Vec3 b, double s) =>
  Vec3.new(a.x + b.x * s, a.y + b.y * s, a.z + b.z * s);

static void _advance(Array bodies, double dt) {
  for (int i = 0; i < bodies.len(); i++) {
    Body body = bodies[i];
    for (int j = i + 1; j < bodies.len(); j++) {
      Body other = bodies[j];
      body.attract(other, dt);
    }
  }
  foreach (Body body in bodies) body.drift(dt);
}

static void Body.attract(Body body, Body other, double dt) {
  Vec3 d = body.position.sub(other.position);
  double distance = sqrt(d.dot(d));
  double magnitude = dt / (distance * distance * distance);
  body.velocity = body.velocity.add_scaled(d.scale(other.mass), -magnitude);
  other.velocity = other.velocity.add_scaled(d.scale(body.mass), magnitude);
}

static inline Vec3 Vec3.sub(Vec3 a, Vec3 b) =>
  Vec3.new(a.x - b.x, a.y - b.y, a.z - b.z);

static inline double Vec3.dot(Vec3 a, Vec3 b) =>
  a.x * b.x + a.y * b.y + a.z * b.z;

static void Body.drift(Body body, double dt) =>
  body.position = body.position.add_scaled(body.velocity, dt);

static double _energy(Array bodies) {
  double total = 0.0;
  for (int i = 0; i < bodies.len(); i++) {
    Body body = bodies[i];
    total += 0.5 * body.mass * body.velocity.dot(body.velocity);
    for (int j = i + 1; j < bodies.len(); j++) {
      Body other = bodies[j];
      Vec3 d = body.position.sub(other.position);
      total -= body.mass * other.mass / sqrt(d.dot(d));
    }
  }
  return total;
}
