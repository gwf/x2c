/*  private-keywords.x -- implementation loop keyword aliases
*/

#pragma once

macro Decorator $private.loop(Stmt $body) {
  while (1) $body
}

keyword loop $private.loop;
