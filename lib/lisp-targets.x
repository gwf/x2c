/*  lisp-targets.x -- evaluator targets of the optional pure modules

    Copyright (c) 2026 Gary William Flake

    The compile-time evaluator binds the pure Json, Diff, and Path operations
    that their `meta native` definitions advertise. This unit builds their
    table so that `lisp.x`, which the implicit prelude includes, does not
    include those modules: every unit replays an included file's includes,
    private ones too, so the prelude would carry their source APIs into every
    program.
*/

#pragma once
$(import "private-keywords.xmacro")
#include "x2c.x"

#pragma private

#include "json.x"
#include "diff.x"

$(import "../etc/lisp-bindings.xlisp")
macro Expression $lisp.optional.target.map() => $(lisp.native.targets
  (filter (lambda (row)
            (let ((name (car row)))
              (not (eq? (+ (String.startswith name "Json_")
                           (String.startswith name "Diff_")
                           (String.startswith name "Path_"))
                        0))))
    (_x2c.native-meta.targets)));

static Map optional_targets = $lisp.optional.target.map();

// The evaluator targets the optional pure modules supply.
Map lisp_optional_native_targets(void) => optional_targets;
