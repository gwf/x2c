#pragma once
#include "x2c.x"

typedef struct Config { int level; } Config;
extern Config config;

alias config.level as level;
alias level * 2 as doubled;
static alias config.level + 100 as private_level;
