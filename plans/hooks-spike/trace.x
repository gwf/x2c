/*  trace.x -- entry and exit tracing for every function

    Including this file hooks every following source function definition
    in the including file: the function prints its name on entry and,
    through `defer`, on every exit. */

#pragma once
#include <stdio.h>

/* Prints the enclosing function's name on entry and on exit. */
macro Decorator $trace.body(Stmt $body) {
  const char *traced = __func__;
  printf("enter %s\n", traced);
  defer printf("exit %s\n", traced);
  $body
}

hook function $trace.body;
