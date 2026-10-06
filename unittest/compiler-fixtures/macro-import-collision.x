#include "x2c.x"

macro Expression $project.collision($value) => $value;

#include "macro-import-collision-defs.x"

int value = $project.collision(41);
