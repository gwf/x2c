/*  scripting.x -- the modules every script unit includes

    Copyright (c) 2026 Gary William Flake

    A source file whose first line is a `#!` line is a script unit, and the
    compiler reads that line as an include of this module. Any program may
    include it to get commands, pipelines, jobs, and path operations
    together.
*/

#pragma once
#include "path.x"
#include "process.x"
