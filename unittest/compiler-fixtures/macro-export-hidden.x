#pragma once

static macro Expression $p.value() => 1;
meta static int p_meta(int n) => n + 1;
static $(defun p_lisp () 2)
meta static int p_static(int n) => n * 3;
