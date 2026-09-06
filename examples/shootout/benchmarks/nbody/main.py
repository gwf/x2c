#!/usr/bin/env python3

from math import pi, sqrt
import sys


SOLAR_MASS = 4 * pi * pi
DAYS_PER_YEAR = 365.24

bodies = [
    [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, SOLAR_MASS],
    [
        4.84143144246472090,
        -1.16032004402742839,
        -0.103622044471123109,
        0.00166007664274403694 * DAYS_PER_YEAR,
        0.00769901118419740425 * DAYS_PER_YEAR,
        -0.0000690460016972063023 * DAYS_PER_YEAR,
        0.000954791938424326609 * SOLAR_MASS,
    ],
    [
        8.34336671824457987,
        4.12479856412430479,
        -0.403523417114321381,
        -0.00276742510726862411 * DAYS_PER_YEAR,
        0.00499852801234917238 * DAYS_PER_YEAR,
        0.0000230417297573763929 * DAYS_PER_YEAR,
        0.000285885980666130812 * SOLAR_MASS,
    ],
    [
        12.8943695621391310,
        -15.1111514016986312,
        -0.223307578892655734,
        0.00296460137564761618 * DAYS_PER_YEAR,
        0.00237847173959480950 * DAYS_PER_YEAR,
        -0.0000296589568540237556 * DAYS_PER_YEAR,
        0.0000436624404335156298 * SOLAR_MASS,
    ],
    [
        15.3796971148509165,
        -25.9193146099879641,
        0.179258772950371181,
        0.00268067772490389322 * DAYS_PER_YEAR,
        0.00162824170038242295 * DAYS_PER_YEAR,
        -0.0000951592254519715870 * DAYS_PER_YEAR,
        0.0000515138902046611451 * SOLAR_MASS,
    ],
]


def offset_momentum():
    px = sum(body[3] * body[6] for body in bodies)
    py = sum(body[4] * body[6] for body in bodies)
    pz = sum(body[5] * body[6] for body in bodies)
    bodies[0][3:6] = -px / SOLAR_MASS, -py / SOLAR_MASS, -pz / SOLAR_MASS


def advance(dt):
    for index, body in enumerate(bodies):
        for other in bodies[index + 1 :]:
            dx = body[0] - other[0]
            dy = body[1] - other[1]
            dz = body[2] - other[2]
            distance = sqrt(dx * dx + dy * dy + dz * dz)
            magnitude = dt / (distance * distance * distance)
            body[3] -= dx * other[6] * magnitude
            body[4] -= dy * other[6] * magnitude
            body[5] -= dz * other[6] * magnitude
            other[3] += dx * body[6] * magnitude
            other[4] += dy * body[6] * magnitude
            other[5] += dz * body[6] * magnitude
    for body in bodies:
        body[0] += dt * body[3]
        body[1] += dt * body[4]
        body[2] += dt * body[5]


def energy():
    total = 0.0
    for index, body in enumerate(bodies):
        total += 0.5 * body[6] * sum(velocity**2 for velocity in body[3:6])
        for other in bodies[index + 1 :]:
            dx = body[0] - other[0]
            dy = body[1] - other[1]
            dz = body[2] - other[2]
            total -= body[6] * other[6] / sqrt(dx * dx + dy * dy + dz * dz)
    return total


offset_momentum()
print(f"{energy():.9f}")
for _ in range(int(sys.argv[1])):
    advance(0.01)
print(f"{energy():.9f}")
