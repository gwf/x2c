/* Representative run, the shootout `local` profile, from this directory:
 *
 *   ../../../../builds/0/x2c build -O2 -DNDEBUG \
 *     --output /tmp/nbody-idiomatic main.x
 *   /tmp/nbody-idiomatic 5000000
 */

/* SPDX-License-Identifier: BSD-3-Clause */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define PI 3.141592653589793
#define SOLAR_MASS (4 * PI * PI)
#define DAYS_PER_YEAR 365.24
#define BODY_COUNT 5

typedef struct Vec3 { double x, y, z; } Vec3;

/* Receiver methods on a value struct name the vector algebra without adding
   a run time representation: each one inlines to the same three scalar
   operations the C spells out by component. `a + b * s` and `a - b * s` stay
   single expressions so clang still fuses each multiply-accumulate. */
static inline Vec3 Vec3.sub(Vec3 a, Vec3 b) {
  return (Vec3) { a.x - b.x, a.y - b.y, a.z - b.z };
}

static inline Vec3 Vec3.scale(Vec3 a, double s) {
  return (Vec3) { a.x * s, a.y * s, a.z * s };
}

static inline Vec3 Vec3.divide(Vec3 a, double s) {
  return (Vec3) { a.x / s, a.y / s, a.z / s };
}

static inline Vec3 Vec3.add_scaled(Vec3 a, Vec3 b, double s) {
  return (Vec3) { a.x + b.x * s, a.y + b.y * s, a.z + b.z * s };
}

static inline Vec3 Vec3.sub_scaled(Vec3 a, Vec3 b, double s) {
  return (Vec3) { a.x - b.x * s, a.y - b.y * s, a.z - b.z * s };
}

static inline double Vec3.dot(Vec3 a, Vec3 b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}

typedef struct Body {
  Vec3 position, velocity;
  double mass;
} Body;

/* Positions in AU, velocities in AU/day, masses in solar masses; main
   scales the last two into the units the integrator uses. */
static Body bodies[BODY_COUNT] = {
  { { 0, 0, 0 }, { 0, 0, 0 }, 1 },
  { { 4.84143144246472090, -1.16032004402742839, -0.103622044471123109 },
    { 1.66007664274403694e-03, 7.69901118419740425e-03,
      -6.90460016972063023e-05 }, 9.54791938424326609e-04 },
  { { 8.34336671824457987, 4.12479856412430479, -0.403523417114321381 },
    { -2.76742510726862411e-03, 4.99852801234917238e-03,
      2.30417297573763929e-05 }, 2.85885980666130812e-04 },
  { { 12.8943695621391310, -15.1111514016986312, -0.223307578892655734 },
    { 2.96460137564761618e-03, 2.37847173959480950e-03,
      -2.96589568540237556e-05 }, 4.36624404335156298e-05 },
  { { 15.3796971148509165, -25.9193146099879641, 0.179258772950371181 },
    { 2.68067772490389322e-03, 1.62824170038242295e-03,
      -9.51592254519715870e-05 }, 5.15138902046611451e-05 }
};

static void _offset_momentum(void) {
  Vec3 momentum = { 0, 0, 0 };
  for (int i = 0; i < BODY_COUNT; i++)
    momentum = momentum.add_scaled(bodies[i].velocity, bodies[i].mass);
  bodies[0].velocity = momentum.divide(-SOLAR_MASS);
}

static void _advance(double dt) {
  for (int i = 0; i < BODY_COUNT; i++) {
    Body *body = &bodies[i];
    for (int j = i + 1; j < BODY_COUNT; j++) {
      Body *other = &bodies[j];
      Vec3 d = body.position.sub(other.position);
      double distance = sqrt(d.dot(d));
      double magnitude = dt / (distance * distance * distance);
      body.velocity =
        body.velocity.sub_scaled(d.scale(other.mass), magnitude);
      other.velocity =
        other.velocity.add_scaled(d.scale(body.mass), magnitude);
    }
  }
  for (int i = 0; i < BODY_COUNT; i++)
    bodies[i].position = bodies[i].position.add_scaled(bodies[i].velocity, dt);
}

static double _energy(void) {
  double total = 0;
  for (int i = 0; i < BODY_COUNT; i++) {
    Body *body = &bodies[i];
    total += 0.5 * body.mass * body.velocity.dot(body.velocity);
    for (int j = i + 1; j < BODY_COUNT; j++) {
      Vec3 d = body.position.sub(bodies[j].position);
      total -= body.mass * bodies[j].mass / sqrt(d.dot(d));
    }
  }
  return total;
}

int main(int argc, char **argv) {
  for (int i = 0; i < BODY_COUNT; i++) {
    bodies[i].velocity = bodies[i].velocity.scale(DAYS_PER_YEAR);
    bodies[i].mass *= SOLAR_MASS;
  }
  _offset_momentum();
  printf("%.9f\n", _energy());
  for (int i = atoi(argv[1]); i; i--) _advance(0.01);
  printf("%.9f\n", _energy());
  return 0;
}
