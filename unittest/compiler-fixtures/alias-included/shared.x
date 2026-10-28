#pragma once
#include "x2c.x"

typedef struct Config { int level; } Config;
extern Config config;

alias config.level as level;
alias doubled to level * 2;
static alias private_level to config.level + 100;
