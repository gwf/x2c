/*  private-keywords.x -- implementation loop decorator
*/

#pragma once

macro Decorator $private.loop(Stmt $body) {
  while (1) $body
}
