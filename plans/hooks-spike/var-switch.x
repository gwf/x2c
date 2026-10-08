/*  var-switch.x -- a switch over a Var reads it as a number

    Including this file registers `var_switch` for every bound and typed
    `switch` statement that follows. A `Var` subject converts to `long` as
    a declared `long` argument converts it, through `x2c_convert`; every
    other switch is declined. Run `x2c run var-switch.x var-switch-test.x`,
    which prints `two three`. */

#pragma once
#include "meta.x"

meta List var_switch(List node) {
  match (node) case %(switch (!set ?subject (expr ("Var") ?)) ?body):
    return %(switch ${x2c_convert(<argument>, subject, %(long))} $body);
  return node;
}

hook <switch> var_switch;
