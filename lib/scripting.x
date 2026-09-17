/*  scripting.x -- the modules every script unit includes

    Copyright (c) 2026 Gary William Flake

    A source file whose first line is a `#!` line is a script unit, and the
    compiler reads that line as an include of this module. Any program may
    include it to get commands, pipelines, jobs, path operations,
    argument parsing, digests, regular expressions, and line differences
    together.
*/

#pragma once
#include "args.x"
#include "diff.x"
#include "digest.x"
#include "path.x"
#include "process.x"
#include "regex.x"
