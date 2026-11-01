/*
 * Copyright (c) 2004-2008 Brent Fulgham, 2005-2015 Isaac Gouy
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 *
 * * Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 *
 * * Neither the name of "The Computer Language Benchmarks Game" nor the name
 *   of "The Computer Language Shootout Benchmarks" nor the names of its
 *   contributors may be used to endorse or promote products derived from this
 *   software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/* The Computer Language Benchmarks Game
 * https://benchmarksgame-team.pages.debian.net/benchmarksgame/
 *
 * contributed by Christoph Bauer
 */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define PI 3.141592653589793
#define SOLAR_MASS (4 * PI * PI)
#define DAYS_PER_YEAR 365.24
#define BODY_COUNT 5

typedef struct Body {
  double x, y, z;
  double vx, vy, vz;
  double mass;
} Body;

static Body bodies[BODY_COUNT] = {
  {
    0.0, 0.0, 0.0,
    0.0, 0.0, 0.0,
    SOLAR_MASS
  },
  {
    4.84143144246472090e+00,
    -1.16032004402742839e+00,
    -1.03622044471123109e-01,
    1.66007664274403694e-03 * DAYS_PER_YEAR,
    7.69901118419740425e-03 * DAYS_PER_YEAR,
    -6.90460016972063023e-05 * DAYS_PER_YEAR,
    9.54791938424326609e-04 * SOLAR_MASS
  },
  {
    8.34336671824457987e+00,
    4.12479856412430479e+00,
    -4.03523417114321381e-01,
    -2.76742510726862411e-03 * DAYS_PER_YEAR,
    4.99852801234917238e-03 * DAYS_PER_YEAR,
    2.30417297573763929e-05 * DAYS_PER_YEAR,
    2.85885980666130812e-04 * SOLAR_MASS
  },
  {
    1.28943695621391310e+01,
    -1.51111514016986312e+01,
    -2.23307578892655734e-01,
    2.96460137564761618e-03 * DAYS_PER_YEAR,
    2.37847173959480950e-03 * DAYS_PER_YEAR,
    -2.96589568540237556e-05 * DAYS_PER_YEAR,
    4.36624404335156298e-05 * SOLAR_MASS
  },
  {
    1.53796971148509165e+01,
    -2.59193146099879641e+01,
    1.79258772950371181e-01,
    2.68067772490389322e-03 * DAYS_PER_YEAR,
    1.62824170038242295e-03 * DAYS_PER_YEAR,
    -9.51592254519715870e-05 * DAYS_PER_YEAR,
    5.15138902046611451e-05 * SOLAR_MASS
  }
};

static void offset_momentum(int count, Body *system) {
  double px = 0.0, py = 0.0, pz = 0.0;
  for (int i = 0; i < count; i++) {
    px += system[i].vx * system[i].mass;
    py += system[i].vy * system[i].mass;
    pz += system[i].vz * system[i].mass;
  }
  system[0].vx = -px / SOLAR_MASS;
  system[0].vy = -py / SOLAR_MASS;
  system[0].vz = -pz / SOLAR_MASS;
}

static void advance(int count, Body *system, double dt) {
  for (int i = 0; i < count; i++) {
    Body *body = &system[i];
    for (int j = i + 1; j < count; j++) {
      Body *other = &system[j];
      double dx = body->x - other->x;
      double dy = body->y - other->y;
      double dz = body->z - other->z;
      double distance = sqrt(dx * dx + dy * dy + dz * dz);
      double magnitude = dt / (distance * distance * distance);
      body->vx -= dx * other->mass * magnitude;
      body->vy -= dy * other->mass * magnitude;
      body->vz -= dz * other->mass * magnitude;
      other->vx += dx * body->mass * magnitude;
      other->vy += dy * body->mass * magnitude;
      other->vz += dz * body->mass * magnitude;
    }
  }
  for (int i = 0; i < count; i++) {
    Body *body = &system[i];
    body->x += dt * body->vx;
    body->y += dt * body->vy;
    body->z += dt * body->vz;
  }
}

static double energy(int count, Body *system) {
  double total = 0.0;
  for (int i = 0; i < count; i++) {
    Body *body = &system[i];
    total += 0.5 * body->mass *
      (body->vx * body->vx + body->vy * body->vy + body->vz * body->vz);
    for (int j = i + 1; j < count; j++) {
      Body *other = &system[j];
      double dx = body->x - other->x;
      double dy = body->y - other->y;
      double dz = body->z - other->z;
      double distance = sqrt(dx * dx + dy * dy + dz * dz);
      total -= body->mass * other->mass / distance;
    }
  }
  return total;
}

int main(int argc, char **argv) {
  int iterations = atoi(argv[1]);
  offset_momentum(BODY_COUNT, bodies);
  printf("%.9f\n", energy(BODY_COUNT, bodies));
  for (int i = 0; i < iterations; i++)
    advance(BODY_COUNT, bodies, 0.01);
  printf("%.9f\n", energy(BODY_COUNT, bodies));
  return 0;
}
