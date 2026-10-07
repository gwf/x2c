/* Two decorators with the same result: one template-only, one through a
   meta call that returns its argument. */
#pragma once
#include "meta.x"

meta List _ident(List body) => %($body);

macro Decorator $ident.tpl(Stmt $body) {
  $body
}

macro Decorator $ident.meta(Stmt $body) {
  $_ident($body)...
}
